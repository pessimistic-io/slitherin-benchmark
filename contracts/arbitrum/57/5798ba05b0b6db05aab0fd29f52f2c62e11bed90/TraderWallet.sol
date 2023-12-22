// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20Upgradeable} from "./ERC20_IERC20Upgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";

import {GMXAdapter} from "./GMXAdapter.sol";
import {BaseVault} from "./BaseVault.sol";

import {UniswapV3Adapter} from "./UniswapV3Adapter.sol";
import {IUniswapV3Router} from "./IUniswapV3Router.sol";
import {IUniswapV3Factory} from "./IUniswapV3Factory.sol";

import {IContractsFactory} from "./IContractsFactory.sol";
import {IAdaptersRegistry} from "./IAdaptersRegistry.sol";
import {IAdapter} from "./IAdapter.sol";
import {IUsersVault} from "./IUsersVault.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {ITraderWallet} from "./ITraderWallet.sol";
import {IDynamicValuation} from "./IDynamicValuation.sol";
import {IERC20MetadataUpgradeable} from "./IERC20MetadataUpgradeable.sol";

contract TraderWallet is BaseVault, ITraderWallet {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    address public override vaultAddress;
    address public override traderAddress;
    uint256 public override cumulativePendingDeposits;
    uint256 public override cumulativePendingWithdrawals;

    // rollover time control
    uint256 public override lastRolloverTimestamp;
    uint256 public rolloverPeriod;

    mapping(address => mapping(address => bool)) public override gmxShortPairs;
    /// @notice arrays of token pairs to make evaluation based on GMX short positions
    address[] public override gmxShortCollaterals;
    address[] public override gmxShortIndexTokens;

    EnumerableSetUpgradeable.UintSet private _traderSelectedProtocolIds;

    /// @notice array of tokens to make evaluation based on balances
    EnumerableSetUpgradeable.AddressSet private _allowedTradeTokens;

    modifier onlyTrader() {
        if (_msgSender() != traderAddress) revert CallerNotAllowed();
        _;
    }

    function initialize(
        address _underlyingTokenAddress,
        address _traderAddress,
        address _ownerAddress
    ) external virtual override initializer {
        __TraderWallet_init(
            _underlyingTokenAddress,
            _traderAddress,
            _ownerAddress
        );
        // _allowedTradeTokens.add(_underlyingTokenAddress);
    }

    function __TraderWallet_init(
        address _underlyingTokenAddress,
        address _traderAddress,
        address _ownerAddress
    ) internal onlyInitializing {
        __BaseVault_init(_underlyingTokenAddress, _ownerAddress);

        __TraderWallet_init_unchained(_underlyingTokenAddress, _traderAddress);
    }

    function __TraderWallet_init_unchained(
        address _underlyingTokenAddress,
        address _traderAddress
    ) internal onlyInitializing {
        _checkZeroAddress(_traderAddress, "_traderAddress");

        _allowedTradeTokens.add(_underlyingTokenAddress);

        traderAddress = _traderAddress;
        rolloverPeriod = 3 hours;

        emit TradeTokenAdded(_underlyingTokenAddress);
    }

    function setVaultAddress(address _vaultAddress) external virtual override {
        // THIS WILL PREVENT THIS WALLET TO BE LINKED WITH ANOTHER VAULT
        if (vaultAddress != address(0)) {
            revert DoubleSet();
        }
        if (msg.sender != contractsFactoryAddress) {
            revert UserNotAllowed();
        }

        vaultAddress = _vaultAddress;

        emit VaultAddressSet(_vaultAddress);
    }

    function setTraderAddress(
        address _traderAddress
    ) external override onlyOwner {
        if (
            !IContractsFactory(contractsFactoryAddress).allowedTraders(
                _traderAddress
            )
        ) revert TraderNotAllowed();

        traderAddress = _traderAddress;

        emit TraderAddressSet(_traderAddress);
    }

    /// @notice Adds pair of tokens which can be used for GMX short position
    /// @dev There is no function to remove such pair, to avoid potential incorrect evaluation of Vault.
    ///      (e.g. case when limit order created then pair removed)
    function addGmxShortPairs(
        address[] calldata collateralTokens,
        address[] calldata indexTokens
    ) external override onlyOwner {
        if (collateralTokens.length != indexTokens.length)
            revert InvalidToken();

        uint256 length = collateralTokens.length;
        for (uint256 i; i < length; ) {
            if (gmxShortPairs[collateralTokens[i]][indexTokens[i]])
                revert InvalidToken();
            if (
                !GMXAdapter.gmxVault.whitelistedTokens(collateralTokens[i]) ||
                !GMXAdapter.gmxVault.stableTokens(collateralTokens[i]) ||
                GMXAdapter.gmxVault.stableTokens(indexTokens[i]) ||
                !GMXAdapter.gmxVault.shortableTokens(indexTokens[i])
            ) revert InvalidToken();

            gmxShortCollaterals.push(collateralTokens[i]);
            gmxShortIndexTokens.push(indexTokens[i]);
            gmxShortPairs[collateralTokens[i]][indexTokens[i]] = true;

            emit NewGmxShortTokens(collateralTokens[i], indexTokens[i]);
            unchecked {
                ++i;
            }
        }
    }

    function addAllowedTradeTokens(
        address[] calldata _tokens
    ) external override onlyTrader {
        address _contractsFactoryAddress = contractsFactoryAddress;

        address uniswapAdapter = _getAdapterAddress(2);
        IUniswapV3Router uniswapV3Router = UniswapV3Adapter(uniswapAdapter)
            .uniswapV3Router();
        address uniswapV3Factory = uniswapV3Router.factory();

        address _underlyingTokenAddress = underlyingTokenAddress;
        
        uint256 length = _tokens.length;
        for (uint256 i; i < length; ) {
            address token = _tokens[i];
            if (
                !IContractsFactory(_contractsFactoryAddress)
                    .isAllowedGlobalToken(token)
            ) revert InvalidToken();

            if (token != _underlyingTokenAddress) {
                address pool = IUniswapV3Factory(uniswapV3Factory).getPool(
                    token,
                    _underlyingTokenAddress,
                    3000 // default UniV3 pool fee
                );
                if (pool == address(0)) {
                    revert NoUniswapPairWithUnderlyingToken(token);
                }
            }

            _allowedTradeTokens.add(token);

            emit TradeTokenAdded(token);

            unchecked {
                ++i;
            }
        }
    }

    function removeAllowedTradeToken(
        address token
    ) external override onlyTrader {
        if (token == underlyingTokenAddress) {
            revert InvalidToken();
        }

        if (!_allowedTradeTokens.remove(token)) revert InvalidToken();

        emit TradeTokenRemoved(token);
    }

    function addProtocolToUse(uint256 protocolId) external override onlyTrader {
        if (!_traderSelectedProtocolIds.add(protocolId))
            revert ProtocolIdPresent();

        if (protocolId != 1) {
            _getAdapterAddress(protocolId);
        }

        emit ProtocolToUseAdded(protocolId);
        /*
            MAKES APPROVAL OF UNDERLYING HERE ???
        */
    }

    function removeProtocolToUse(
        uint256 protocolId
    ) external override onlyTrader {
        if (!_traderSelectedProtocolIds.remove(protocolId))
            revert ProtocolIdNotPresent();

        emit ProtocolToUseRemoved(protocolId);
    }

    //
    function traderDeposit(uint256 _amount) external override onlyTrader {
        if (_amount == 0) revert ZeroAmount();

        uint256 _cumulativePendingWithdrawals = cumulativePendingWithdrawals;
        if (_cumulativePendingWithdrawals > 0) {
            if (_amount > _cumulativePendingWithdrawals) {
                // case when trader requests to withdraw 100 tokens and then deposits 120 tokens

                uint256 transferAmount = _amount -
                    _cumulativePendingWithdrawals; // from trader to contract

                delete cumulativePendingWithdrawals;
                cumulativePendingDeposits += transferAmount;

                IERC20Upgradeable(underlyingTokenAddress).safeTransferFrom(
                    _msgSender(),
                    address(this),
                    transferAmount
                );
            } else {
                // case when trader requests to withdraw 100 tokens and then deposits 80 tokens

                // uint256 transferAmount = 0; // from trader to contract

                cumulativePendingWithdrawals =
                    _cumulativePendingWithdrawals -
                    _amount;
            }
        } else {
            // case when trader deposits 100 tokens without withdraw requests

            cumulativePendingDeposits += _amount;

            IERC20Upgradeable(underlyingTokenAddress).safeTransferFrom(
                _msgSender(),
                address(this),
                _amount
            );
        }

        emit TraderDeposit(_msgSender(), _amount, currentRound);
    }

    function withdrawRequest(uint256 _amount) external override onlyTrader {
        _checkZeroRound();
        if (_amount == 0) revert ZeroAmount();

        uint256 _cumulativePendingDeposits = cumulativePendingDeposits;
        if (_cumulativePendingDeposits > 0) {
            uint256 transferAmount; // from contract to trader

            if (_cumulativePendingDeposits >= _amount) {
                // case when trader deposits 100 tokens and then requests to withdraw 80 tokens

                transferAmount = _amount;

                cumulativePendingDeposits =
                    _cumulativePendingDeposits -
                    _amount;
            } else {
                // case when trader deposits 100 tokens and then requests to withdraw 120 tokens
                transferAmount = _cumulativePendingDeposits;

                delete cumulativePendingDeposits;
                cumulativePendingWithdrawals +=
                    _amount -
                    _cumulativePendingDeposits;
            }

            IERC20Upgradeable(underlyingTokenAddress).safeTransfer(
                _msgSender(),
                transferAmount
            );
        } else {
            // case when trader requests to withdraw 100 tokens without deposits

            cumulativePendingWithdrawals += _amount;
        }

        emit WithdrawRequest(_msgSender(), _amount, currentRound);
    }

    function setAdapterAllowanceOnToken(
        uint256 _protocolId,
        address _tokenAddress,
        bool _revoke
    ) external override onlyTrader {
        if (!_traderSelectedProtocolIds.contains(_protocolId))
            revert InvalidAdapter();

        if (!_allowedTradeTokens.contains(_tokenAddress)) revert InvalidToken();

        uint256 amount;
        if (!_revoke) amount = type(uint256).max;

        IERC20Upgradeable(_tokenAddress).forceApprove(
            _getAdapterAddress(_protocolId),
            amount
        );
    }

    // not sure if the execution is here. Don't think so
    function rollover() external override {
        if (lastRolloverTimestamp + rolloverPeriod > block.timestamp) {
            revert TooEarly();
        }

        uint256 _cumulativePendingDeposits = cumulativePendingDeposits;
        uint256 _cumulativePendingWithdrawals = cumulativePendingWithdrawals;

        uint256 _currentRound = currentRound;

        uint256 _newAfterRoundBalance;
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();
        address _underlyingTokenAddress = underlyingTokenAddress;

        if (_currentRound != 0) {
            _newAfterRoundBalance = getContractValuation();
        } else {
            uint256 tokenBalance = IERC20Upgradeable(_underlyingTokenAddress).balanceOf(
                address(this)
            );

            _newAfterRoundBalance = IDynamicValuation(dynamicValuationAddress)
                .getOraclePrice(_underlyingTokenAddress, tokenBalance);
        }

        IUsersVault(vaultAddress).rolloverFromTrader();

        if (_cumulativePendingWithdrawals > 0) {
            // send to trader account
            IERC20Upgradeable(_underlyingTokenAddress).safeTransfer(
                traderAddress,
                _cumulativePendingWithdrawals
            );

            delete cumulativePendingWithdrawals;
        }

        // put to zero this value so the round can start
        if (_cumulativePendingDeposits > 0) {
            delete cumulativePendingDeposits;
        }

        // get profits
        int256 overallProfit;
        if (_currentRound != 0) {
            overallProfit =
                int256(_newAfterRoundBalance) -
                int256(afterRoundBalance); // 0 <= old < new => overallProfit = new - old > 0
        }
        if (overallProfit > 0) {
            // DO SOMETHING HERE WITH PROFIT
            // PROFIT IS CALCULATED IN ONE TOKEN
            // BUT PROFIT IS DISTRIBUTED AMONG OPEN POSITIONS
            // AND DIFFERENT TOKEN BALANCES
        }

        uint256 ONE_UNDERLYING_TOKEN = _ONE_UNDERLYING_TOKEN;
        uint256 underlyingPrice = IDynamicValuation(dynamicValuationAddress)
                .getOraclePrice(_underlyingTokenAddress, ONE_UNDERLYING_TOKEN);
        int256 overallProfitInUnderlyingToken = overallProfit * int256(ONE_UNDERLYING_TOKEN) / int256(underlyingPrice);

        // get values for next round proportions
        afterRoundBalance = _newAfterRoundBalance;
        currentRound = _currentRound + 1;
        lastRolloverTimestamp = block.timestamp;

        emit TraderWalletRolloverExecuted(
            block.timestamp,
            _currentRound,
            overallProfitInUnderlyingToken,
            IERC20Upgradeable(_underlyingTokenAddress).balanceOf(address(this))
        );
    }

    function executeOnProtocol(
        uint256 _protocolId,
        IAdapter.AdapterOperation memory _traderOperation,
        bool _replicate
    ) public override nonReentrant {
        if (_msgSender() != traderAddress && _msgSender() != vaultAddress)
            revert CallerNotAllowed();
        _checkZeroRound();

        if (!_traderSelectedProtocolIds.contains(_protocolId))
            revert InvalidProtocol();

        uint256 ratio;
        address _vaultAddress = vaultAddress;
        // execute operation with ratio equals to 0 because it is for trader, not scaling
        if (_protocolId == 1) {
            ratio = _executeOnGmx(
                true, // called by traderWallet
                address(this),
                _vaultAddress,
                ratio,
                _traderOperation
            );
        } else {
            // update ratio for further usersVault operation
            ratio = _executeOnAdapter(
                _getAdapterAddress(_protocolId),
                true, // called by traderWallet
                address(this),
                _vaultAddress,
                ratio,
                _traderOperation
            );
        }

        // contract should receive tokens HERE
        emit OperationExecuted(
            _protocolId,
            block.timestamp,
            "trader wallet",
            _replicate,
            ratio
        );

        // if tx needs to be replicated on vault
        if (_replicate) {
            IUsersVault(_vaultAddress).executeOnProtocol(
                _protocolId,
                _traderOperation,
                ratio
            );

            emit OperationExecuted(
                _protocolId,
                block.timestamp,
                "users vault",
                _replicate,
                ratio
            );
        }
    }

    function getAdapterAddressPerProtocol(
        uint256 protocolId
    ) external view override returns (address) {
        return _getAdapterAddress(protocolId);
    }

    function isAllowedTradeToken(
        address token
    ) external view override returns (bool) {
        return _allowedTradeTokens.contains(token);
    }

    function allowedTradeTokensLength()
        external
        view
        override
        returns (uint256)
    {
        return _allowedTradeTokens.length();
    }

    function allowedTradeTokensAt(
        uint256 index
    ) external view override returns (address) {
        return _allowedTradeTokens.at(index);
    }

    function getAllowedTradeTokens()
        public
        view
        override
        returns (address[] memory)
    {
        return _allowedTradeTokens.values();
    }

    function isTraderSelectedProtocol(
        uint256 protocolId
    ) external view override returns (bool) {
        return _traderSelectedProtocolIds.contains(protocolId);
    }

    function traderSelectedProtocolIdsLength()
        external
        view
        override
        returns (uint256)
    {
        return _traderSelectedProtocolIds.length();
    }

    function traderSelectedProtocolIdsAt(
        uint256 index
    ) external view override returns (uint256) {
        return _traderSelectedProtocolIds.at(index);
    }

    function getTraderSelectedProtocolIds()
        external
        view
        override
        returns (uint256[] memory)
    {
        return _traderSelectedProtocolIds.values();
    }

    function getContractValuation() public view override returns (uint256) {
        // VALUATE CONTRACT AND POSITIONS HERE !!!
        address dynamicValuationAddress = IContractsFactory(
            contractsFactoryAddress
        ).dynamicValuationAddress();
        uint256 totalWalletFundsValuation = IDynamicValuation(
            dynamicValuationAddress
        ).getDynamicValuation(address(this));

        uint256 pendingsFunds = cumulativePendingDeposits +
            cumulativePendingWithdrawals;
        uint256 pendingsFundsValuation = IDynamicValuation(
            dynamicValuationAddress
        ).getOraclePrice(underlyingTokenAddress, pendingsFunds);

        if (pendingsFundsValuation > totalWalletFundsValuation) return 0;

        return (totalWalletFundsValuation - pendingsFundsValuation);
    }

    function getGmxShortCollaterals()
        external
        view
        override
        returns (address[] memory)
    {
        return gmxShortCollaterals;
    }

    function getGmxShortIndexTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return gmxShortIndexTokens;
    }
}

