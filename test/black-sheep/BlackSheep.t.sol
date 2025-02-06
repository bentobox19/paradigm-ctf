// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "forge-std/Test.sol";
import "foundry-huff/HuffConfig.sol";

import "../../src/black-sheep/ISimpleBank.sol";
import "../../src/black-sheep/Challenge.sol";

contract BlackSheepTest is Test {
  address private challengeAddress;

  function setUp() public {
    HuffConfig config = new HuffConfig();
    ISimpleBank bank = ISimpleBank(config.deploy("black-sheep/SimpleBank"));
    payable(address(bank)).transfer(10 ether);
    challengeAddress = address(new Challenge(bank));
  }

  function testExploit() public {
    // This
    // function withdraw(bytes32, uint8, bytes32, bytes32) external payable;

    assertEq(address(Challenge(challengeAddress).BANK()).balance, 0);
  }
}
