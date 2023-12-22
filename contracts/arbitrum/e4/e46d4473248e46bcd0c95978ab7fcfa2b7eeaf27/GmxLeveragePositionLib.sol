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

interface IFundManager {
    function successCallBack() external;

    function failCallBack() external;
}

interface IVault {
    function getOwner() external view returns (address);
}

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
contract GmxLeveragePositionLib is
    GmxLeveragePositionDataDecoder,
    IGmxLeveragePosition,
    IPositionRouterCallbackReceiver
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
    using AddressArrayLib for address[];

    struct PendingPositionParams {
        address collateralToken;
        address indexToken;
        bool isLong;
        bool isIncrease;
        address vaultProxy;
        uint256 amountToTransfer;
        uint256 size;
    }

    uint256 public constant GMX_FUNDING_RATE_PRECISION = 1000000;

    uint256 public constant BASIS_POINTS_DIVISOR = 10000;

    address private immutable GMX_POSITION_ROUTER;
    address private immutable VALUE_INTERPRETER;
    address private immutable GMX_ROUTER;

    address private immutable GMX_VAULT;
    address private immutable GMX_READER;

    address public immutable WETH_TOKEN;

    address[] internal collateralAssets;

    address[] internal supportedIndexTokens;

    mapping(bytes32 => PendingPositionParams) public pendingPositions;

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
                bytes32 _referralCode
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
                _referralCode
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
        bytes32 _referralCode
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

        __addIndexTokens(_indexToken);

        // Update local storage

        pendingPositions[_requestKey] = PendingPositionParams({
            collateralToken: _path[0],
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
        IWETH(payable(WETH_TOKEN)).withdraw(_executionFee);
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
            collateralToken: _path[0],
            indexToken: _indexToken,
            isLong: _isLong,
            isIncrease: false,
            vaultProxy: msg.sender,
            amountToTransfer: _collateralDelta,
            size: _sizeDelta
        });
    }

    function __removeCollateralAssets() private {
        uint256 len = collateralAssets.length;
        uint256[] memory amounts = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            require(
                assetIsCollateral(collateralAssets[i]),
                "__removeCollateralAssets: Invalid collateral asset"
            );

            uint256 collateralBalance = ERC20(collateralAssets[i]).balanceOf(address(this));

            if (collateralBalance != 0)
                ERC20(collateralAssets[i]).safeTransfer(msg.sender, amounts[i]);
        }

        uint256 arrayLen = supportedIndexTokens.length;

        for (uint256 i; i < arrayLen; ++i) {
            address indexToken = supportedIndexTokens[i];
            require(
                assetIsIndexToken(indexToken),
                "__removeCollateralAssets: Invalid index token"
            );

            uint256 collateralBalance = ERC20(indexToken).balanceOf(address(this));

            if (collateralBalance != 0)
                ERC20(indexToken).safeTransfer(msg.sender, collateralBalance);
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
        pure
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
    // @return amounts_ Managed asset amounts
    function getManagedAssets()
        external
        view
        override
        returns (address[] memory assets_, uint256[] memory amounts_)
    {
        uint256 count = supportedIndexTokens.length;

        if (collateralAssets.length != 0) {
            assets_ = new address[](count + 1);
            amounts_ = new uint256[](count + 1);
            assets_[0] = collateralAssets[0];
            amounts_[0] = ERC20(assets_[0]).balanceOf(address(this));
        }

        for (uint256 j; j < count; ++j) {
            address indexToken = supportedIndexTokens[j];
            assets_[j + 1] = indexToken;

            (
                uint256 longSize,
                uint256 positionCollateral,
                ,
                uint256 _entryFundingRate,
                ,
                ,
                ,

            ) = IGmxVault(getGmxVault()).getPosition(address(this), indexToken, indexToken, true);

            if (longSize != 0) {
                // Calculate amount after fees for long position
                uint256 usdOutAfterFee = getUsdOutAfterFee(
                    longSize,
                    positionCollateral,
                    _entryFundingRate,
                    indexToken,
                    indexToken,
                    true
                );
                uint256 amount = IGmxVault(getGmxVault()).usdToTokenMin(
                    indexToken,
                    usdOutAfterFee
                );

                amounts_[j + 1] += amount;
            }
            // Get short position details
            (
                uint256 shortSize,
                uint256 shortCollateral,
                ,
                uint256 entryFundingRate,
                ,
                ,
                ,

            ) = IGmxVault(getGmxVault()).getPosition(address(this), assets_[0], indexToken, false);

            if (shortSize != 0) {
                uint256 usdOutAfterFee = getUsdOutAfterFee(
                    shortSize,
                    shortCollateral,
                    entryFundingRate,
                    assets_[0],
                    indexToken,
                    false
                );

                uint256 amount = IGmxVault(getGmxVault()).usdToTokenMin(
                    assets_[0],
                    usdOutAfterFee
                );
                amounts_[0] += amount;
            }

            amounts_[j + 1] += ERC20(assets_[j + 1]).balanceOf(address(this));
        }

        return (assets_, amounts_);
    }

    function getUsdOutAfterFee(
        uint256 size,
        uint256 positionCollateral,
        uint256 entryFundingRate,
        address collateralToken,
        address indexToken,
        bool isLong
    ) private view returns (uint256) {
        (bool hasProfit, uint256 adjustedDelta) = IGmxVault(getGmxVault()).getPositionDelta(
            address(this),
            collateralToken,
            indexToken,
            isLong
        );

        uint256 usdOut;
        // transfer profits out
        if (hasProfit && adjustedDelta > 0) usdOut = adjustedDelta;

        if (!hasProfit && adjustedDelta > 0)
            positionCollateral = positionCollateral - adjustedDelta;

        usdOut = usdOut + positionCollateral;

        uint256 feeUsd = size.sub(getPositionFee(size));

        uint256 fundingFee = getFundingFee(size, collateralToken, entryFundingRate);

        uint256 totalFee = feeUsd + fundingFee;

        uint256 usdOutAfterFee = usdOut > totalFee ? usdOut - totalFee : usdOut;

        return usdOutAfterFee;
    }

    function getPositionFee(uint256 size) public view returns (uint256) {
        return
            size
                .mul(BASIS_POINTS_DIVISOR.sub(IGmxVault(getGmxVault()).marginFeeBasisPoints()))
                .div(BASIS_POINTS_DIVISOR);
    }

    function getFundingFee(
        uint256 size,
        address collateralToken,
        uint256 entryFundingRate
    ) public view returns (uint256) {
        uint256 fundingRate = (
            IGmxVault(getGmxVault()).cumulativeFundingRates(collateralToken).sub(entryFundingRate)
        );
        return size.mul(fundingRate).div(GMX_FUNDING_RATE_PRECISION);
    }

    ///////////////////
    // CallBack Handle //
    ///////////////////

    function gmxPositionCallback(
        bytes32 _requestKey,
        bool _isExecuted,
        bool _isIncrease
    ) external override {
        _onlyPositionRouter();
        PendingPositionParams memory params = pendingPositions[_requestKey];
        if (_isExecuted) {
            _successCallback(_requestKey, _isExecuted, params);
        } else {
            _failCallback(_requestKey, _isIncrease, params);
        }

        emit GmxPositionCallback(msg.sender, _requestKey, _isExecuted, _isIncrease);
    }

    function _successCallback(
        bytes32 _requestKey,
        bool _isIncrease,
        PendingPositionParams memory params
    ) private {
        // PendingPositionParams memory params = pendingPositions[_requestKey];

        IFundManager(IVault(params.vaultProxy).getOwner()).successCallBack();

        if (_isIncrease)
            emit PositionIncreased(
                params.collateralToken,
                params.indexToken,
                params.isLong,
                params.size
            );
        else
            emit PositionDecreased(
                params.collateralToken,
                params.indexToken,
                params.isLong,
                params.size
            );

        delete pendingPositions[_requestKey];
    }

    function _failCallback(
        bytes32 _requestKey,
        bool _isIncrease,
        PendingPositionParams memory params
    ) private {
        if (_isIncrease) {
            ERC20(params.collateralToken).safeTransfer(params.vaultProxy, params.amountToTransfer);
        }

        IFundManager(IVault(params.vaultProxy).getOwner()).successCallBack();

        emit ExecutionFailed(
            params.collateralToken,
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
        address[] memory assets;

        assets = supportedIndexTokens;

        for (uint256 j; j < assets.length; ++j) {
            address indexToken = assets[j];
            (uint256 longPositionSize, , , , , , , ) = IGmxVault(getGmxVault()).getPosition(
                address(this),
                indexToken,
                indexToken,
                true
            );
            if (longPositionSize != 0) {
                ++count;
            }

            for (uint256 i; i < collateralAssets.length; ++i) {
                (uint256 shortPositionSize, , , , , , , ) = IGmxVault(getGmxVault()).getPosition(
                    address(this),
                    collateralAssets[i],
                    indexToken,
                    false
                );
                if (shortPositionSize != 0) {
                    ++count;
                }
            }
        }
        return count;
    }

    function getOpenPositions(
        address user,
        address[] memory indexTokens,
        address[] memory collateralTokens
    ) public view override returns (bytes32[] memory keys, uint256 count) {
        //Possible gmx positions are 20 for any address for now
        keys = new bytes32[](20);

        for (uint256 j; j < indexTokens.length; ++j) {
            address indexToken = indexTokens[j];
            (uint256 size, , , , , , , ) = IGmxVault(getGmxVault()).getPosition(
                user,
                indexToken,
                indexToken,
                true
            );
            if (size != 0) {
                bytes32 key = getPositionKey(user, indexToken, indexToken, true);
                keys[count] = key;
                ++count;
            }
            for (uint256 i; i < collateralTokens.length; ++i) {
                (uint256 shortPositionSize, , , , , , , ) = IGmxVault(getGmxVault()).getPosition(
                    user,
                    collateralTokens[i],
                    indexToken,
                    false
                );
                if (shortPositionSize != 0) {
                    bytes32 key = getPositionKey(user, collateralTokens[i], indexToken, false);
                    keys[count] = key;
                    ++count;
                }
            }
        }

        return (keys, count);
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

