// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "./SafeMath.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./IPositionRouter.sol";
import "./IRouter.sol";
import "./IGmxVault.sol";
import "./GmxLeveragePositionDataDecoder.sol";
import "./IGmxLeveragePosition.sol";
import {IPositionRouterCallbackReceiver} from "./IPositionRouterCallbackReceiver.sol";
import "./AddressArrayLib.sol";

// import {IWETH} from "../../../../interfaces/IWETH.sol";

interface IWETH {
    function deposit() external payable;

    function withdraw(uint256) external;
}

/// @title GMXLeveragePositionLib Contract
/// @author Alfred Council <security@alfred.capital>
/// @notice An External Position library contract for taking gmx leverage positions
/// @title GMXLeveragePositionLib Contract
/// @author Alfred Council <security@alfred.capital>
/// @notice An External Position library contract for taking gmx leverage positions
contract GmxLeveragePositionLib is GmxLeveragePositionDataDecoder, IGmxLeveragePosition {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using AddressArrayLib for address[];

    struct PendingPositionParams {
        address collateral;
        address indexToken;
        bool isLong;
        bool isIncrease;
        address vaultProxy;
        uint256 amountToTransfer;
        uint256 size;
    }

    address private immutable GMX_POSITION_ROUTER;
    address private immutable VALUE_INTERPRETER;
    address private immutable GMX_ROUTER;

    address private immutable GMX_VAULT;
    address private immutable GMX_READER;

    address public immutable WETH_TOKEN;

    address[] internal collateralAssets;

    address[] internal supportedIndexTokens;

    mapping(bytes32 => PendingPositionParams) private pendingPositions;

    event GmxPositionCallback(
        address keeper,
        bytes32 requestKey,
        bool isExecuted,
        bool isIncrease
    );

    constructor(
        address _gmxPositionRouter,
        address _gmxVault,
        address _gmxReader,
        address _gmxRouter,
        address _valueInterpreter,
        address _weth
    ) public {
        GMX_POSITION_ROUTER = _gmxPositionRouter;
        GMX_VAULT = _gmxVault;
        GMX_READER = _gmxReader;
        GMX_ROUTER = _gmxRouter;
        VALUE_INTERPRETER = _valueInterpreter;
        WETH_TOKEN = _weth;
    }

    /// @notice Initializes the external position
    /// @dev Nothing to initialize for this contract
    function init(bytes memory) external override {}

    function assetIsCollateral(address _asset) public view returns (bool isCollateral_) {
        return collateralAssets.contains(_asset);
    }

    function assetIsIndexToken(address _asset) public view returns (bool isIndex_) {
        return supportedIndexTokens.contains(_asset);
    }

    /// @notice Receives and executes a call from the Vault
    /// @param _actionData Encoded data to execute the action
    function receiveCallFromVault(bytes memory _actionData) external override {
        (uint256 actionId, bytes memory actionArgs) = abi.decode(_actionData, (uint256, bytes));
        if (
            actionId ==
            uint256(IGmxLeveragePosition.GmxLeveragePositionActions.CreateIncreasePosition)
        ) {
            (
                address[] memory _path,
                address _indexToken,
                uint256 _amount,
                uint256 _minOut,
                uint256 _sizeDelta,
                bool _isLong,
                uint256 _acceptablePrice,
                uint256 _executionFee,
                bytes32 _referralCode,
                address _callbackTarget
            ) = __decodeCreateIncreasePositionActionArgs(actionArgs);

            __createIncreasePosition(
                _path,
                address(_indexToken),
                _amount,
                _minOut,
                _sizeDelta,
                _isLong,
                _acceptablePrice,
                _executionFee,
                _referralCode,
                _callbackTarget
            );
        } else if (
            actionId ==
            uint256(IGmxLeveragePosition.GmxLeveragePositionActions.CreateDecreasePosition)
        ) {
            (
                address[] memory path,
                address indexToken,
                uint256 collateralDelta,
                uint256 sizeDelta,
                bool isLong,
                uint256 acceptablePrice,
                uint256 minOut,
                uint256 executionFee,
                bool withdrawETH
            ) = __decodeCreateDecreaseActionArgs(actionArgs);

            __createDecreasePosition(
                path,
                indexToken,
                collateralDelta,
                sizeDelta,
                isLong,
                address(msg.sender),
                acceptablePrice,
                minOut,
                executionFee,
                withdrawETH,
                address(this)
            );
        } else if (
            actionId == uint256(IGmxLeveragePosition.GmxLeveragePositionActions.RemoveCollateral)
        ) {
            __removeCollateralAssets();
        } else {
            revert("receiveCallFromVault: Invalid actionId");
        }
    }

    // PRIVATE FUNCTIONS

    /// @dev Approve assets to GMX Router contract

    /// @dev Helper to approve a target account with the max amount of an asset
    function __approveAsset(address _asset, address _target, uint256 _neededAmount) internal {
        uint256 allowance = ERC20(_asset).allowance(address(this), _target);
        if (allowance < _neededAmount) {
            if (allowance > 0) {
                ERC20(_asset).safeApprove(_target, 0);
            }
            ERC20(_asset).safeApprove(_target, _neededAmount);
        }

        //call approvePlugin function on gmx position router
        IRouter(getGmxRouter()).approvePlugin(getPositionRouter());
        __addCollateralAssets(WETH_TOKEN);

        __addCollateralAssets(_asset);
    }

    /// @dev Mints a new uniswap position, receiving an nft as a receipt
    function __createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amount,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 _referralCode,
        address _callbackTarget
    ) private {
        // Grant max token approval to the position router as necessary
        __approveAsset(_path[0], getGmxRouter(), _amount);

        IWETH(payable(WETH_TOKEN)).withdraw(_executionFee);

        // create increase position on Gmx
        bytes32 _requestKey = IPositionRouter(getPositionRouter()).createIncreasePosition{
            value: _executionFee
        }(
            _path,
            address(_indexToken),
            _amount,
            _minOut,
            _sizeDelta,
            _isLong,
            _acceptablePrice,
            _executionFee,
            _referralCode,
            address(this)
        );
        // Update local storage

        pendingPositions[_requestKey] = PendingPositionParams({
            collateral: _path[0],
            indexToken: _indexToken,
            isLong: _isLong,
            isIncrease: true,
            amountToTransfer: _amount,
            vaultProxy: msg.sender,
            size: _sizeDelta
        });
    }

    function __addCollateralAssets(address _asset) private {
        if (!assetIsCollateral(_asset)) {
            collateralAssets.push(_asset);
            // emit CollateralAssetAdded(aTokens[i]);
        }
    }

    function __addIndexTokens(address _asset) private {
        if (!assetIsIndexToken(_asset)) {
            supportedIndexTokens.push(_asset);
            // emit CollateralAssetAdded(aTokens[i]);
        }
    }

    function __createDecreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _collateralDelta,
        uint256 _sizeDelta,
        bool _isLong,
        address _receiver,
        uint256 _acceptablePrice,
        uint256 _minOut,
        uint256 _executionFee,
        bool _withdrawETH,
        address _callbackTarget
    ) private {
        IWETH(WETH_TOKEN).withdraw(_executionFee);
        require(address(this).balance >= _executionFee, "insufficient exec fee");
        bytes32 _requestKey = IPositionRouter(getPositionRouter()).createDecreasePosition{
            value: _executionFee
        }(
            _path,
            _indexToken,
            _collateralDelta,
            _sizeDelta,
            _isLong,
            _receiver,
            _acceptablePrice,
            _minOut,
            _executionFee,
            _withdrawETH,
            _callbackTarget
        );

        pendingPositions[_requestKey] = PendingPositionParams({
            collateral: _path[0],
            indexToken: _indexToken,
            isLong: _isLong,
            isIncrease: false,
            vaultProxy: msg.sender,
            amountToTransfer: _collateralDelta,
            size: _sizeDelta
        });
    }

    function __removeCollateralAssets() private {
        uint256[] memory amounts = new uint256[](collateralAssets.length);
        for (uint256 i; i < collateralAssets.length; i++) {
            require(
                assetIsCollateral(collateralAssets[i]),
                "__removeCollateralAssets: Invalid collateral asset"
            );

            uint256 collateralBalance = ERC20(collateralAssets[i]).balanceOf(address(this));

            if (amounts[i] == type(uint256).max) {
                amounts[i] = collateralBalance;
            }

            // If the full collateral of an asset is removed, it can be removed from collateral assets

            ERC20(collateralAssets[i]).safeTransfer(msg.sender, amounts[i]);
        }
    }

    ////////////////////
    // POSITION VALUE //
    ////////////////////

    // EXTERNAL FUNCTIONS

    /// @notice Retrieves the debt assets (negative value) of the external position
    /// @return assets_ Debt assets
    /// @return amounts_ Debt asset amounts
    function getDebtAssets()
        external
        override
        returns (address[] memory assets_, uint256[] memory amounts_)
    {
        return (assets_, amounts_);
    }

    // WETH->WETH : Long Position
    // usdc->WETH : short Position,
    // DAI -> WETH : short Position
    // usdt -> WETH : short Position

    // @notice Retrieves the managed assets (positive value) of the external position
    // @return assets_ Managed assets
    // / @return amounts_ Managed asset amounts
    function getManagedAssets()
        external
        override
        returns (address[] memory collateralAssets_, uint256[] memory amounts_)
    {
        collateralAssets_ = collateralAssets;
        amounts_ = new uint256[](collateralAssets.length);

        address indexToken = supportedIndexTokens[0];

        //     uint256 aggregated;
        for (uint256 i; i < collateralAssets_.length; ++i) {
            amounts_[i] = ERC20(collateralAssets_[i]).balanceOf(address(this));

            //This can be wbtc as well (need to extend)

            bool isLong = collateralAssets_[i] == indexToken;

            (
                uint256 size,
                uint256 positionCollateral,
                ,
                uint256 entryFundingRate,
                ,
                ,
                ,

            ) = IGmxVault(getGmxVault()).getPosition(
                    address(this),
                    collateralAssets_[i],
                    indexToken,
                    isLong
                );

            if (size != 0) {
                (bool hasProfit, uint256 adjustedDelta) = IGmxVault(getGmxVault())
                    .getPositionDelta(address(this), collateralAssets_[i], indexToken, isLong);
                // uint256 feeUsd = IGmxVault(getGmxVault()).getPositionFee( // testing
                //     address(this),
                //     collateralAssets_[i],
                //     indexToken,
                //     isLong,
                //     positionCollateral //console this
                // );
                // console.log('fusd', feeUsd);

                // uint256 fundingFee = IGmxVault(getGmxVault()).getFundingFee(
                //     address(this),
                //     collateralAssets_[i],
                //     indexToken,
                //     isLong,
                //     size,
                //     entryFundingRate
                // );

                uint256 usdOut;
                // transfer profits out
                if (hasProfit && adjustedDelta > 0) {
                    usdOut = adjustedDelta;
                }
                if (!hasProfit && adjustedDelta > 0) {
                    positionCollateral = positionCollateral - adjustedDelta;
                }
                usdOut = usdOut + positionCollateral;
                // positionCollateral = 0;
                // }

                // feeUsd = feeUsd + fundingFee;
                //         // if the usdOut is more than the fee then deduct the fee from the usdOut directly
                //         // else deduct the fee from the position's collateral
                uint256 usdOutAfterFee = usdOut;
                // if (usdOut > feeUsd)
                //     //TODO :use safemath here
                //     usdOutAfterFee = usdOut - (feeUsd);

                // console.log('**********',usdOutAfterFee);
                amounts_[i] += usdOutAfterFee;
                // console.log('**********',amounts_[i]);
            }
        }
        return (collateralAssets_, amounts_);
    }

    ///////////////////
    // CallBack Handle //
    ///////////////////

    function gmxPositionCallback(
        bytes32 _requestKey,
        bool _isExecuted,
        bool _isIncrease
    ) external {
        _onlyPositionRouter();
        if (_isExecuted) {
            _successCallback(_requestKey);
        } else {
            _failCallback(_requestKey, _isIncrease);
        }

        emit GmxPositionCallback(msg.sender, _requestKey, _isExecuted, _isIncrease);
    }

    function _successCallback(bytes32 _requestKey) private {
        PendingPositionParams memory params = pendingPositions[_requestKey];

        __addIndexTokens(params.indexToken);
        emit PositionAdded(
            address(this),
            params.collateral,
            params.indexToken,
            params.isLong,
            params.isIncrease,
            params.size
        );
        delete pendingPositions[_requestKey];
    }

    function _failCallback(bytes32 _requestKey, bool _isIncrease) private {
        PendingPositionParams memory params = pendingPositions[_requestKey];

        if (_isIncrease) {
            ERC20(params.collateral).safeTransfer(params.vaultProxy, params.amountToTransfer);
        }

        IWETH(WETH_TOKEN).deposit{value: getMinExecutionFee()}();

        ERC20(params.indexToken).safeTransfer(params.vaultProxy, getMinExecutionFee());

        emit ExecutionFailed(
            params.vaultProxy,
            params.collateral,
            params.indexToken,
            params.isLong,
            params.isIncrease,
            params.size
        );
        delete pendingPositions[_requestKey];
    }

    //Require for PositionCallBack Interface
    function isContract() external pure returns (bool) {
        return true;
    }

    function getPositionKey(
        address _account,
        address _collateralToken,
        address _indexToken,
        bool _isLong
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_account, _collateralToken, _indexToken, _isLong));
    }

    function getOpenPositionsCount() public view override returns (uint256) {
        uint256 count;
        for (uint256 i; i < collateralAssets.length; ++i) {
            //This can be wbtc as well (need to extend)
            address indexToken = WETH_TOKEN;
            bool isLong = collateralAssets[i] == indexToken;
            (uint256 size, , , , , , , ) = IGmxVault(getGmxVault()).getPosition(
                address(this),
                collateralAssets[i],
                indexToken,
                isLong
            );
            if (size != 0) {
                ++count;
            }
        }
        return count;
    }

    function _onlyPositionRouter() internal view {
        require(msg.sender == getPositionRouter(), "invalid positionRouter");
    }

    ///////////////////
    // STATE GETTERS //
    ///////////////////

    function getMinExecutionFee() public view returns (uint256) {
        return IPositionRouter(getPositionRouter()).minExecutionFee();
    }

    function getGmxVault() public view returns (address gmxVault_) {
        return GMX_VAULT;
    }

    function getGmxRouter() public view returns (address router_) {
        return GMX_ROUTER;
    }

    function getPositionRouter() public view returns (address positionRouter_) {
        return GMX_POSITION_ROUTER;
    }

    /// @notice Gets the `VALUE_INTERPRETER` variable
    /// @return valueInterpreter_ The `NON_FUNGIBLE_TOKEN_MANAGER` variable value
    function getValueInterpreter() public view returns (address valueInterpreter_) {
        return VALUE_INTERPRETER;
    }
}

