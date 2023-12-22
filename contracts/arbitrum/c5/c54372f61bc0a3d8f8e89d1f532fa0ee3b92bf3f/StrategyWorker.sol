// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Strategy Worker.
 * @author  André Ferreira

  * @dev    VERSION: 1.0
 *          DATE:    2023.08.29
*/

import "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {TreasuryVault} from "./TreasuryVault.sol";
import {AutomatedVaultERC4626, IAutomatedVaultERC4626, IERC20} from "./AutomatedVaultERC4626.sol";
import {Math} from "./Math.sol";
import {PercentageMath} from "./percentageMath.sol";
import {IUniswapV2Router} from "./IUniswapV2Router.sol";
import {ConfigTypes} from "./ConfigTypes.sol";

contract StrategyWorker {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using PercentageMath for uint256;

    address public dexRouter;
    address public controller;
    // address public strategiesTreasuryVault;

    event StrategyActionExecuted(
        address indexed vault,
        address indexed depositor,
        address tokenIn,
        uint256 tokenInAmount,
        address[] tokensOut,
        uint256[] tokensOutAmounts,
        uint256 feeAmount
    );

    constructor(address _dexRouter, address _controller) {
        dexRouter = _dexRouter;
        controller = _controller;
    }

    modifier onlyController() {
        require(msg.sender == controller, "Only controller can call this");
        _;
    }

    function executeStrategyAction(
        address _strategyVaultAddress,
        address _depositorAddress
    ) external onlyController {
        AutomatedVaultERC4626 _strategyVault = AutomatedVaultERC4626(
            _strategyVaultAddress
        );

        (
            address _depositAsset,
            address[] memory _buyAssets,
            uint256[] memory _buyAmounts
        ) = _getSwapParams(_strategyVault);

        ConfigTypes.InitMultiAssetVaultParams
            memory initMultiAssetVaultParams = _strategyVault
                .getInitMultiAssetVaultParams();

        uint256 _actionFeePercentage = initMultiAssetVaultParams
            .treasuryPercentageFeeOnBalanceUpdate;
        address payable _protocolTreasuryAddress = initMultiAssetVaultParams
            .treasury;
        uint256 _amountToWithdraw;
        uint256[] memory _buyAmountsAfterFee;
        uint256 _totalFee;

        (
            _amountToWithdraw,
            _buyAmountsAfterFee,
            _totalFee
        ) = _calculateAmountsAfterFee(_buyAmounts, _actionFeePercentage);

        uint256 _totalBuyAmount = _amountToWithdraw - _totalFee;

        _strategyVault.setLastUpdate();

        _strategyVault.withdraw(
            _amountToWithdraw,
            address(this), //receiver
            _depositorAddress //owner
        );

        address[2] memory spenders = [dexRouter, _protocolTreasuryAddress];
        _ensureApprovedERC20(_depositAsset, spenders);

        uint256[] memory _swappedAssetAmounts = _swapTokens(
            _depositorAddress,
            _depositAsset,
            _buyAssets,
            _buyAmountsAfterFee
        );

        TreasuryVault(_protocolTreasuryAddress).depositERC20(
            _totalFee,
            _depositAsset
        );

        emit StrategyActionExecuted(
            _strategyVaultAddress,
            _depositorAddress,
            _depositAsset,
            _totalBuyAmount,
            _buyAssets,
            _swappedAssetAmounts,
            _totalFee
        );
    }

    function _getSwapParams(
        AutomatedVaultERC4626 _strategyVault
    )
        private
        view
        returns (
            address _depositAsset,
            address[] memory _buyAssets,
            uint256[] memory _buyAmounts
        )
    {
        ConfigTypes.InitMultiAssetVaultParams
            memory _initMultiAssetVaultParams = _strategyVault
                .getInitMultiAssetVaultParams();
        _depositAsset = address(_initMultiAssetVaultParams.depositAsset);
        _buyAssets = _strategyVault.getBuyAssetAddresses();
        _buyAmounts = _strategyVault.getStrategyParams().buyAmounts;
    }

    function _calculateAmountsAfterFee(
        uint256[] memory _buyAmounts,
        uint256 _actionFeePercentage
    )
        private
        returns (
            uint256 _amountToWithdraw,
            uint256[] memory _buyAmountsAfterFee,
            uint256 _totalFee
        )
    {
        uint256 _buyAmountsLength = _buyAmounts.length;
        _buyAmountsAfterFee = new uint256[](_buyAmountsLength);
        for (uint256 i = 0; i < _buyAmountsLength; i++) {
            uint256 _buyAmount = _buyAmounts[i];
            uint256 _feeAmount = _buyAmount.percentMul(_actionFeePercentage);
            _totalFee += _feeAmount;
            uint256 _buyAmountAfterFee = _buyAmount - _feeAmount;
            _buyAmountsAfterFee[i] = _buyAmountAfterFee;
            _amountToWithdraw += _buyAmount;
        }
        require(
            _amountToWithdraw > 0,
            "Total buyAmount must be greater than zero"
        );
    }

    function _swapTokens(
        address _depositorAddress,
        address _depositAsset,
        address[] memory _buyAssets,
        uint256[] memory _buyAmountsAfterFee
    ) internal returns (uint256[] memory _amountsOut) {
        uint256 _buyAssetsLength = _buyAssets.length;
        _amountsOut = new uint256[](_buyAssetsLength);
        for (uint256 i = 0; i < _buyAssets.length; i++) {
            uint256 amountOut = _swapToken(
                _depositorAddress,
                _depositAsset,
                _buyAssets[i],
                _buyAmountsAfterFee[i]
            );
            _amountsOut[i] = amountOut;
        }
    }

    function _swapToken(
        address _depositorAddress,
        address _depositAsset,
        address _buyAsset,
        uint256 _buyAmountAfterFee
    ) internal returns (uint256 _amountOut) {
        address[] memory _path = new address[](2);
        _path[0] = _depositAsset;
        _path[1] = _buyAsset;

        uint256[] memory _amountsOut = IUniswapV2Router(dexRouter)
            .swapExactTokensForTokens(
                _buyAmountAfterFee,
                0, // AmountOutMin (set to 0 for simplicity)
                _path,
                _depositorAddress, // swapped tokens sent directly to vault depositor
                block.timestamp + 600 //
            );
        uint256 _amountsOutLength = _amountsOut.length;
        _amountOut = _amountsOut[_amountsOutLength - 1]; // amounts out contains results from all the pools in the choosen route
    }

    function _ensureApprovedERC20(
        address tokenAddress,
        address[2] memory spenders
    ) private {
        IERC20 token = IERC20(tokenAddress);

        for (uint256 i = 0; i < spenders.length; i++) {
            uint256 currentAllowance = token.allowance(
                address(msg.sender),
                spenders[i]
            );
            if (currentAllowance == 0) {
                token.approve(spenders[i], type(uint256).max);
            }
        }
    }
}

