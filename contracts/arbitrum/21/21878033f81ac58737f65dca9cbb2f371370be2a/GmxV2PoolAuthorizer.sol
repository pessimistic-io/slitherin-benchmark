// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.19;

import "./BaseACL.sol";
import "./EnumerableSet.sol";

struct CreateDepositParams {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address initialLongToken;
    address initialShortToken;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    uint256 minMarketTokens;
    bool shouldUnwrapNativeToken;
    uint256 executionFee;
    uint256 callbackGasLimit;
}

struct CreateWithdrawalParams {
    address receiver;
    address callbackContract;
    address uiFeeReceiver;
    address market;
    address[] longTokenSwapPath;
    address[] shortTokenSwapPath;
    uint256 minLongTokenAmount;
    uint256 minShortTokenAmount;
    bool shouldUnwrapNativeToken;
    uint256 executionFee;
    uint256 callbackGasLimit;
}

contract GmxV2PoolAuthorizer is BaseACL {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant NAME = "GmxV2PoolAuthorizer";
    uint256 public constant VERSION = 1;

    address public constant GMX_EXCHANGE_ROUTER = 0x7C68C7866A64FA2160F78EEaE12217FFbf871fa8;
    address public constant GMX_DEPOSIT_VAULT = 0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55;
    address public constant GMX_WITHDRAWAL_VAULT = 0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55;

    struct CollateralPair {
        address longCollateral;
        address shortCollateral;
    }
    mapping(address => CollateralPair) public authorizedPools;

    address public safeAccount;

    constructor(
        address owner_, 
        address caller_, 
        address safeAccount_,
        address[] memory gmTokens_,
        CollateralPair[] memory collateralPairs_
    ) BaseACL(owner_, caller_) {
        safeAccount = safeAccount_;

        require(gmTokens_.length == collateralPairs_.length, "array length not matches");
        for (uint256 i = 0; i < gmTokens_.length; i++) {
            _addGmxPool(gmTokens_[i], collateralPairs_[i]);
        }
    }

    event AddGmxPool(address indexed gmToken, CollateralPair collateralPair);
    event RemoveGmxPool(address indexed gmToken);

    function addGmxPool(address gmToken_, CollateralPair calldata collateralPair_) external onlyOwner {
        _addGmxPool(gmToken_, collateralPair_);
    }

    function _addGmxPool(address gmToken_, CollateralPair memory collateralPair_) internal {
        require(
            gmToken_ != address(0) && 
            collateralPair_.longCollateral != address(0) && 
            collateralPair_.shortCollateral != address(0), 
            "invalid token addresses"
        );
        authorizedPools[gmToken_] = collateralPair_;
        emit AddGmxPool(gmToken_, collateralPair_);
    }

    function removeGmxPool(address gmToken_) external onlyOwner {
        _removeGmxPool(gmToken_);
    }

    function _removeGmxPool(address gmToken_) internal {
        delete authorizedPools[gmToken_];
        emit RemoveGmxPool(gmToken_);
    }

    function isPoolAuthorized(address gmToken_) public view returns (bool) {
        return authorizedPools[gmToken_].longCollateral != address(0);
    }

    function contracts() public pure override returns (address[] memory _contracts) {
        _contracts = new address[](1);
        _contracts[0] = GMX_EXCHANGE_ROUTER;
    }

    function _check(bytes memory data) internal view returns (bool) {
        (bool success,) = address(this).staticcall(data);
        return success;
    }

    function multicall(bytes[] calldata data) external view onlyContract(GMX_EXCHANGE_ROUTER) {
        require(data.length == 2 || data.length == 3, "invalid data length");
        uint256 value = _txn().value;
        bytes4 operation = bytes4(data[data.length - 1]);

        if (operation == this.createDeposit.selector) {
            (CreateDepositParams memory depositParams) = abi.decode(data[data.length - 1][4:], (CreateDepositParams));
            createDeposit(depositParams);

            // for deposit operations, the first call should be `sendWnt` and the receiver should be GmxDepositVault
            require(bytes4(data[0]) == this.sendWnt.selector, "sendWnt error");
            (address wntReceiver, uint256 amount) = abi.decode(data[0][4:], (address, uint256));
            require(wntReceiver == GMX_DEPOSIT_VAULT, "invalid wnt receiver");
            require(amount == value, "invalid wnt amount");

            // for deposit operations with non-ETH tokens, the second call should be `sendTokens`
            if (data.length == 3) {
                require(bytes4(data[1]) == this.sendTokens.selector, "sendTokens error");
                (address token, address tokenReceiver,) = abi.decode(data[1][4:], (address, address, uint256));
                CollateralPair memory collateralPair = authorizedPools[depositParams.market];
                require(token == collateralPair.longCollateral || token == collateralPair.shortCollateral, "token not authorized");
                require(tokenReceiver == GMX_DEPOSIT_VAULT, "invalid token receiver");
            }

        } else if (operation == this.createWithdrawal.selector) {
            (CreateWithdrawalParams memory withdrawalParams) = abi.decode(data[data.length - 1][4:], (CreateWithdrawalParams));
            createWithdrawal(withdrawalParams);

            // for withdrawal operations, the first call should be `sendWnt` and the receiver should be GmxWithdrawalVault
            require(bytes4(data[0]) == this.sendWnt.selector, "sendWnt error");
            (address wntReceiver, uint256 amount) = abi.decode(data[0][4:], (address, uint256));
            require(wntReceiver == GMX_WITHDRAWAL_VAULT, "invalid wnt receiver");
            require(amount == value, "invalid wnt amount");

            // for withdrawal operations, the second call should be `sendTokens` and the receiver should be GmxWithdrawalVault
            require(bytes4(data[1]) == this.sendTokens.selector, "sendTokens error");
            (address token, address tokenReceiver,) = abi.decode(data[1][4:], (address, address, uint256));
            require(token == withdrawalParams.market, "GM token not matches");
            require(tokenReceiver == GMX_WITHDRAWAL_VAULT, "invalid token receiver");

        } else {
            revert("not deposit or withdraw operation");
        }
    }

    function sendWnt(address /** receiver */, uint256 /** amount */) external view onlyContract(GMX_EXCHANGE_ROUTER) {
        revert("sendWnt not allowed");
    }

    function sendTokens(address /** token */, address /** receiver */, uint256 /** amount */) external view onlyContract(GMX_EXCHANGE_ROUTER) {
        revert("sendTokens not allowed");
    }

    function createDeposit(CreateDepositParams memory depositParams) public view onlyContract(GMX_EXCHANGE_ROUTER) {
        require(isPoolAuthorized(depositParams.market), "pool not authorized");
        require(depositParams.receiver == safeAccount, "invalid deposit receiver");
        require(depositParams.callbackContract == address(0), "deposit callback not allowed");
    }

    function createWithdrawal(CreateWithdrawalParams memory withdrawalParams) public view onlyContract(GMX_EXCHANGE_ROUTER) {
        require(isPoolAuthorized(withdrawalParams.market), "pool not authorized");
        require(withdrawalParams.receiver == safeAccount, "invalid withdrawal receiver");
        require(withdrawalParams.callbackContract == address(0), "withdrawal callback not allowed");
    }
}

