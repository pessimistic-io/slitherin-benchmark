// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { AddressUpgradeable } from "./AddressUpgradeable.sol";

import { IGMXExecutor } from "./IGMXExecutor.sol";
import { IGmxRewardRouter } from "./IGmxRewardRouter.sol";
import { IWETH } from "./IWETH.sol";
import { IAddressProvider } from "./IAddressProvider.sol";

contract GMXExecutor is Initializable, ReentrancyGuardUpgradeable, OwnableUpgradeable, IGMXExecutor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;

    address private constant ZERO = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address public addressProvider;
    address public wethAddress;
    address public depositor;

    modifier onlyDepositor() {
        require(depositor == msg.sender, "GMXExecuter: Caller is not the depositor");
        _;
    }

    // @custom:oz-upgrades-unsafe-allow constructor
    // solhint-disable-next-line no-empty-blocks
    constructor() initializer {}

    function initialize(
        address _addressProvider,
        address _wethAddress,
        address _depositor
    ) external initializer {
        require(_addressProvider != address(0), "GMXExecuter: _addressProvider cannot be 0x0");
        require(_wethAddress != address(0), "GMXExecuter: _wethAddress cannot be 0x0");
        require(_depositor != address(0), "GMXExecuter: _depositor cannot be 0x0");

        require(_addressProvider.isContract(), "GMXExecuter: _addressProvider is not a contract");
        require(_wethAddress.isContract(), "GMXExecuter: _wethAddress is not a contract");
        require(_depositor.isContract(), "GMXExecuter: _depositor is not a contract");

        __Ownable_init();
        __ReentrancyGuard_init();

        addressProvider = _addressProvider;
        wethAddress = _wethAddress;
        depositor = _depositor;

        _transferOwnership(_depositor);
    }

    function mint(address _token, uint256 _amountIn) external payable override nonReentrant onlyDepositor returns (address, uint256) {
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amountIn);

        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        _approve(_token, IGmxRewardRouter(router).glpManager(), _amountIn);

        uint256 amountOut = IGmxRewardRouter(router).mintAndStakeGlp(_token, _amountIn, 0, 0);

        return (IGmxRewardRouter(router).stakedGlpTracker(), amountOut);
    }

    function withdraw(
        address _tokenOut,
        uint256 _amountIn,
        uint256 _minOut
    ) public override onlyDepositor returns (uint256) {
        address router = IAddressProvider(addressProvider).getGmxRewardRouter();

        return IGmxRewardRouter(router).unstakeAndRedeemGlp(_tokenOut, _amountIn, _minOut, depositor);
    }

    function claimRewards() external override nonReentrant onlyDepositor returns (uint256) {
        bool shouldClaimGmx = true;
        bool shouldStakeGmx = false;
        bool shouldClaimEsGmx = true;
        bool shouldStakeEsGmx = false;
        bool shouldStakeMultiplierPoints = false;
        bool shouldClaimWeth = true;
        bool shouldConvertWethToEth = false;

        uint256 before = IERC20Upgradeable(wethAddress).balanceOf(address(this));
        address router = IAddressProvider(addressProvider).getGmxRewardRouterV1();

        IGmxRewardRouter(router).handleRewards(
            shouldClaimGmx,
            shouldStakeGmx,
            shouldClaimEsGmx,
            shouldStakeEsGmx,
            shouldStakeMultiplierPoints,
            shouldClaimWeth,
            shouldConvertWethToEth
        );

        uint256 rewards = IERC20Upgradeable(wethAddress).balanceOf(address(this)) - before;

        IERC20Upgradeable(wethAddress).safeTransfer(depositor, rewards);

        return rewards;
    }

    function _approve(
        address _token,
        address _spender,
        uint256 _amount
    ) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }
}

