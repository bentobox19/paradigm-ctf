// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Bringing the deps like Deploy.s.sol does
import "../../src/dai-plus-plus/Challenge.sol";
import "../../src/dai-plus-plus/SystemConfiguration.sol";
import {Account as Acct} from "../../src/dai-plus-plus/Account.sol";

// Deploy.s.sol is able to find `AccountManager`...
import "../../src/dai-plus-plus/AccountManager.sol";

contract DaiPlusPlusTest is Test {
  address private challengeAddress;

  function setUp() public {
    // Aping Deploy.s.sol
    SystemConfiguration configuration = new SystemConfiguration();
    AccountManager manager = new AccountManager(configuration);

    configuration.updateAccountManager(address(manager));
    configuration.updateStablecoin(address(new Stablecoin(configuration)));
    configuration.updateAccountImplementation(address(new Acct()));
    configuration.updateEthUsdPriceFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    configuration.updateSystemContract(address(manager), true);

    challengeAddress = address(new Challenge(configuration));
  }

  function testExploit() public pure {
    console.log("Something Something LOL");
  }
}
