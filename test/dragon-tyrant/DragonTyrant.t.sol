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

  function testExploit() public {
    // We win when
    // TOKEN.balanceOf(address(TOKEN)) == 0;
    assertFalse(Challenge(challengeAddress).isSolved());



    // assertTrue(Challenge(challengeAddress).isSolved());
  }
}
