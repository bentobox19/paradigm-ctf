// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin-4.9.2/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-4.9.2/contracts/token/ERC20/IERC20.sol";

import "../../src/dodont/Challenge.sol";

interface CloneFactoryLike {
  function clone(address) external returns (address);
}

interface DVMLike {
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
}

contract QuoteToken is ERC20 {
    constructor() ERC20("Quote Token", "QT") {
        _mint(msg.sender, 1_000_000 ether);
    }
}

contract DodontTest is Test {
  CloneFactoryLike private immutable CLONE_FACTORY = CloneFactoryLike(0x5E5a7b76462E4BdF83Aa98795644281BdbA80B88);
  address private immutable DVM_TEMPLATE = 0x2BBD66fC4898242BDBD2583BBe1d76E8b8f71445;
  IERC20 private immutable WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

  address private immutable deployerAddress = makeAddr("deployer");
  address private immutable playerAddress = makeAddr("player");

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

    DVMLike dvm = DVMLike(CLONE_FACTORY.clone(DVM_TEMPLATE));
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

    // Write down the problem
    // Think real hard
    // Write down the solution

    vm.stopPrank();
    // assertTrue(Challenge(challengeAddress).isSolved());
  }
}
