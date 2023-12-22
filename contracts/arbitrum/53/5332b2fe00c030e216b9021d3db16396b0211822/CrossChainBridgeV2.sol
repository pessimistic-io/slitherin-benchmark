/*
 * SPDX-License-Identifier: Apache-2.0
 */
pragma solidity ^0.8.8;

import "./IERC20Upgradeable.sol";
import "./ERC20PresetMinterPauserUpgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./SafeMathUpgradeable.sol";

import "./ICrossChainFunctionCall.sol";
import "./NonAtomicHiddenAuthParameters.sol";
import "./FeeTracker.sol";
import "./BalanceTracker.sol";

/**
 * Cross chain bridge using the Simple Function Call protocol.
 *
 */
contract CrossChainBridgeV2 is
    NonAtomicHiddenAuthParameters,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    FeeTracker,
    BalanceTracker
{
    using SafeMathUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    enum TokenProcessMethod {
        // Token has not been added to the bridge yet.
        NONE,
        // Tokens of this type are minted when transferred to this blockchain and burn
        // when transferred to another blockchain.
        MINTER,
        // Tokens of this type are kept in escrow when transferred from this chain.
        // That is, transferFrom is used, and not mint or burn.
        MASS_CONSERVATION
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");
    bytes32 public constant REFUNDER_ROLE = keccak256("REFUNDER");
    bytes32 public constant FEE_COLLECTOR_ROLE = keccak256("FEE_COLLECTOR");

    ICrossChainFunctionCall public crossChainControl;

    uint256 public myBcId;

    // Addresses of bridges on other blockchains.
    mapping(uint256 => address) public remoteBridges;

    // Addresses of bridges on other blockchains.
    mapping(address => uint256) public feeReserves;

    // ***************************************************************************
    // ******* Token configuration below here ************************************
    // ***************************************************************************
    //
    // This mapping is used to determine how tokens should
    // be processed when cross-blockchain transfers occur.
    //
    // For native coin, the address is
    // 0x0000000000000000000000000000000000000001
    //
    // Map (token contract address on this blockchain =>
    //  token contract configuration)
    mapping(address => TokenProcessMethod) public tokenProcessMethods;

    // Mapping of token address on this blockchain to token address
    // of the same type on different blockchains.
    //
    // Map (token address on this blockchain =>
    //  Map (destination blockchain Id => destination token address)
    mapping(address => mapping(uint256 => address)) private tokenAddressMapping;

    // Mapping of token address on this blockchain and minimum
    //  transfer amount required for a cross-chain transactions.
    //
    // !!! AMOUNT DECIMALS MUST MATCH TOKEN'S DECIMALS !!!
    //
    // Map (token address on this blockchain => minimum transfer amount)
    mapping(address => uint256) public tokenMinimumTransferAmount;

    // Mapping of token address on this blockchain and it's corresponding decimals
    //
    // Map (token address on this blockchain => decimals)
    mapping(address => uint256) public tokenDecimals;

    // Mapping of token address on this blockchain and collect fee method
    //
    // Map (token address on this blockchain => minimum transfer amount)
    mapping(address => CollectFeeMethod) private _tokenCollectFeeMethod;

    // Mapping of token address on this blockchain and fee percentage
    //
    // Map (token address on this blockchain => fee percentage)
    mapping(address => uint256) public tokenFeePercentage;

    // Mapping of token address on this blockchain and flat fee amount in Wei
    //
    // Map (token address on this blockchain => flat fee amount)
    mapping(address => uint256) public tokenFeeFlatAmount;

    // Mapping of token address on this blockchain and maximum fee amount can be collected
    //
    // Map (token address on this blockchain => max fee amount)
    mapping(address => uint256) public tokenMaxFeeAmount;

    /**
     * Indicates a request to transfer some tokens has occurred on this blockchain.
     *
     * @param txId               Tx ID of the transaction.
     * @param destBcId           Blockchain the tokens are being transferred to.
     * @param srcToken           Address of the token contract on this blockchain.
     * @param destToken          Address of the token contract on destination blockchain.
     * @param sender             Address sending the tokens.
     * @param recipient          Address to transfer the tokens to on the target blockchain.
     * @param amount             Amount of tokens to transfer.
     */
    event TransferTo(
        bytes32 txId,
        uint256 srcBcId,
        uint256 destBcId,
        address srcToken,
        address destToken,
        address sender,
        address recipient,
        uint256 amount,
        uint256 amountAfterFee
    );

    /**
     * Indicates a transfer request has been received on this blockchain.
     *
     * @param srcBcId            Blockchain the tokens are being transferred from.
     * @param srcToken           Address of the token contract on source blockchain.
     * @param destToken          Address of the token contract on this blockchain.
     * @param recipient          Address to transfer the tokens to on the this blockchain.
     * @param amount             Amount of tokens to transfer.
     */
    event ReceivedFrom(
        uint256 srcBcId,
        address srcToken,
        address destToken,
        address recipient,
        uint256 amount
    );

    /**
     * Update the mapping between an contract on this blockchain and a contract on another blockchain.
     *
     * @param srcToken      Address of contract on this blockchain.
     * @param destBcId      Blockchain ID where the corresponding contract resides.
     * @param destToken     Address of contract on the other blockchain.
     */
    event TokenMappingUpdated(
        address srcToken,
        uint256 destBcId,
        address destToken
    );

    /**
     * Token process method configuration has been set / been changed.
     *
     * @param srcToken               Address of token on this blockchain.
     * @param decimals               Decimals of token on this blockchain.
     * @param minTransferAmount      Minimum amount required for a transaction.
     * @param processMethod          Process method for token on this blockchain.
     * @param collectFeeMethod       Collect fee method for token on this blockchain.
     */
    event TokenConfigUpdated(
        address srcToken,
        uint256 decimals,
        uint256 minTransferAmount,
        TokenProcessMethod processMethod,
        CollectFeeMethod collectFeeMethod
    );

    /**
     * Indicate an administrative transfer has occurred.
     *
     * @param token            Token to transfer.
     * @param recipient        Address to transfer the tokens to.
     * @param amount           Amount of tokens to transfer.
     */
    event Refunded(address token, address recipient, uint256 amount);

    /**
     * Indicate an migration has occurred.
     *
     * @param token             Token to transfer.
     * @param newContract       Address to transfer the tokens to.
     * @param amount            Amount of tokens migrated.
     */
    event MigratedTo(address token, address newContract, uint256 amount);

    /**
     * Indicates an amount has been added to fee reserves on this blockchain.
     *
     * @param token              Token address from this blockchain.
     * @param amount             Fee amount collected, and transfer to FeeTracker contract.
     */
    event FeeCollected(address token, uint256 amount);

    /**
     * Indicates an amount has been added to fee reserves on this blockchain.
     *
     * @param token              Token address from this blockchain.
     * @param recipient          Recipient from this blockchain.
     * @param amount             Fee amount collected, and transfer to FeeTracker contract.
     */
    event FeeWithdrawn(address token, address recipient, uint256 amount);

    /**
     * Initialize the contract.
     *
     * @param _crossChainControl    Simple Function Call protocol implementation.
     * @param _operator             Operator role address.
     * @param _pauser               Pauser role address.
     * @param _refunder             Refunder role address.
     */
    function initialize(
        uint256 _myBcId,
        address _crossChainControl,
        address _operator,
        address _pauser,
        address _refunder
    ) public initializer {
        __ReentrancyGuard_init();
        __AccessControl_init();
        __Pausable_init();

        myBcId = _myBcId;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(OPERATOR_ROLE, _operator);
        _setupRole(PAUSER_ROLE, _pauser);
        _setupRole(REFUNDER_ROLE, _refunder);

        crossChainControl = ICrossChainFunctionCall(_crossChainControl);
    }

    /**
     * Transfer tokens from msg.sender to this contract on this blockchain,
     * and request tokens on the remote blockchain be given to the requested
     * account on the destination blockchain.
     *
     * NOTE: msg.sender must have called approve() on the token contract.
     *
     * @param _destBcId         Destination blockchain ID.
     * @param _srcToken         Address of contract on this blockchain.
     * @param _recipient        Address of account to transfer tokens to on the destination blockchain.
     * @param _amount           Amount of tokens to transfer. Must be >= tokenMinimumTransferAmount.
     */
    function transferToOtherBlockchain(
        uint256 _destBcId,
        address _srcToken,
        address _recipient,
        uint256 _amount
    ) external payable whenNotPaused nonReentrant {
        address destBridge = remoteBridges[_destBcId];
        _validate(
            destBridge != address(0),
            "POSI Bridge: Blockchain not supported"
        );

        // The token must be able to be transferred to the target blockchain.
        address destToken = tokenAddressMapping[_srcToken][_destBcId];
        _validate(
            destToken != address(0),
            "POSI Bridge: Token not transferable to requested blockchain"
        );

        if (_isNativeCoin(_srcToken)) {
            _validate(msg.value == _amount, "POSI Bridge: Incorrect amount");
        }

        uint256 minTransferAmt = tokenMinimumTransferAmount[_srcToken];
        _validate(
            _amount >= minTransferAmt,
            "POSI Bridge: Amount below minimum transfer amount"
        );

        // Transfer tokens from the user to this contract.
        // The transfer will revert if the account has inadequate balance or if adequate
        // allowance hasn't been set-up.
        _transferOrBurn(_srcToken, msg.sender, _amount);

        (uint256 amountAfterFee, ) = _collectFee(_srcToken, _amount);
        _validate(amountAfterFee > 0, "POSI Bridge: Amount after fee is zero");

        bytes32 txId = crossChainControl.crossBlockchainCall(
            _destBcId,
            destBridge,
            abi.encodeWithSelector(
                this.receiveFromOtherBlockchain.selector,
                destToken,
                _recipient,
                amountAfterFee
            )
        );

        emit TransferTo(
            txId,
            myBcId,
            _destBcId,
            _srcToken,
            destToken,
            msg.sender,
            _recipient,
            _amount,
            amountAfterFee
        );
    }

    /**
     * Transfer tokens that are owned by this contract to a recipient. The tokens have
     * effectively been transferred from another blockchain to this blockchain.
     *
     * @param _destToken          Address of the token being transferred.
     * @param _recipient          Account to transfer ownership of the tokens to.
     * @param _amount             The number of tokens to be transferred.
     */
    function receiveFromOtherBlockchain(
        address _destToken,
        address _recipient,
        uint256 _amount
    ) external payable whenNotPaused {
        _validate(
            _msgSender() == address(crossChainControl),
            "POSI Bridge: Can not process transfers from contracts other than the bridge contract"
        );

        (uint256 srcBcId, address srcBridge) = decodeNonAtomicAuthParams();
        // The source blockchain id is validated at the function call layer. No need to check
        // that it isn't zero.

        _validate(srcBridge != address(0), "Bridge: caller contract is 0");
        address destBridge = remoteBridges[srcBcId];
        _validate(
            destBridge != address(0),
            "POSI Bridge: No Bridge supported for source blockchain"
        );
        _validate(
            srcBridge == destBridge,
            "POSI Bridge: Incorrect source Bridge"
        );

        _transferOrMint(_destToken, _recipient, _amount);

        emit ReceivedFrom(srcBcId, srcBridge, _destToken, _recipient, _amount);
    }

    /**
     * Indicates whether a token can be transferred to (or from) a blockchain.
     *
     * @param _bcId          Blockchain id of other blockchain.
     * @param _token         Address of token contract on this blockchain.
     * @return bool          True if the token can be transferred to (or from) a blockchain.
     */
    function isBcIdTokenAllowed(
        uint256 _bcId,
        address _token
    ) public view returns (bool) {
        return address(0) != tokenAddressMapping[_token][_bcId];
    }

    /**
     * Gets the mapping between an contract on this blockchain and the contract on
     * another blockchain.
     *
     * @param _bcId          Blockchain id of other blockchain.
     * @param _token         Address of token contract on this blockchain.
     * @return address       Contract address of token contract on other blockchain.
     */
    function getBcIdTokenMapping(
        uint256 _bcId,
        address _token
    ) public view returns (address) {
        return tokenAddressMapping[_token][_bcId];
    }

    function getRemoteBridgeContract(
        uint256 _bcId
    ) external view returns (address) {
        return remoteBridges[_bcId];
    }

    function feePercentage(
        address _token
    ) public view override returns (uint256) {
        return tokenFeePercentage[_token];
    }

    function flatFeeAmount(
        address _token
    ) public view override returns (uint256) {
        return tokenFeeFlatAmount[_token];
    }

    function tokenCollectFeeMethod(
        address _token
    ) public view override returns (CollectFeeMethod) {
        return _tokenCollectFeeMethod[_token];
    }

    function maxFeeAmount(
        address _token
    ) public view override returns (uint256) {
        return tokenMaxFeeAmount[_token];
    }

    function availableBalance(
        address _token
    ) public view override returns (uint256) {
        uint256 balance = _isNativeCoin(_token)
            ? address(this).balance
            : IERC20Upgradeable(_token).balanceOf(address(this));
        return balance.sub(feeReserves[_token]);
    }

    // ***************************************************************************
    // ******* Only Role below here *********************************************
    // ***************************************************************************
    /**

    /**
     * Pauses the bridge.
     *
     * Requirements:
     * - the caller must have the `PAUSER_ROLE`.
     *
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * Unpauses the bridge.
     *
     * Requirements:
     * - the caller must have the `PAUSER_ROLE`.
     *
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Add a token mapping and set the token contract configuration. This can
     * only be called if the token has not been set-up yet.
     *
     * Requirements:
     * - the caller must have the `OPERATOR_ROLE`.
     *
     * @param _srcToken             Address of contract on this blockchain.
     * @param _destBcId             Blockchain ID where the corresponding contract resides.
     * @param _destToken            Address of contract on the other blockchain.
     * @param _processMethod        Process method for token on this blockchain to use.
     */
    function addContractFirstMapping(
        address _srcToken,
        uint256 _destBcId,
        address _destToken,
        uint256 _decimals,
        uint256 _minTransferAmount,
        uint256 _feePercentage,
        uint256 _feeFlatAmount,
        uint256 _maxFeeAmount,
        TokenProcessMethod _processMethod,
        CollectFeeMethod _collectFeeMethod
    ) external onlyRole(OPERATOR_ROLE) {
        //        _validate(
        //            !_tokenExists(_srcToken),
        //            "POSI Bridge: token already configured"
        //        );

        _setTokenConfig(
            _srcToken,
            _decimals,
            _minTransferAmount,
            _feePercentage,
            _feeFlatAmount,
            _maxFeeAmount,
            _processMethod,
            _collectFeeMethod
        );
        _updateContractMapping(_srcToken, _destBcId, _destToken);
    }

    /**
     * @dev Set the token configuration after the token has first been added. The ONLY reason
     * to call this function is that when the contract was first added, it was added with
     * the wrong value.
     *
     * Requirements:
     * - the caller must have the `OPERATOR_ROLE`.
     *
     * @param _srcToken             Address of contract on this blockchain.
     * @param _processMethod        Process method for token on this blockchain to use.
     */
    function setTokenConfig(
        address _srcToken,
        uint256 _decimals,
        uint256 _minTransferAmount,
        uint256 _feePercentage,
        uint256 _feeFlatAmount,
        uint256 _maxFeeAmount,
        TokenProcessMethod _processMethod,
        CollectFeeMethod _collectFeeMethod
    ) external onlyRole(OPERATOR_ROLE) {
        _validate(_tokenExists(_srcToken), "POSI Bridge: token not configured");
        _setTokenConfig(
            _srcToken,
            _decimals,
            _minTransferAmount,
            _feePercentage,
            _feeFlatAmount,
            _maxFeeAmount,
            _processMethod,
            _collectFeeMethod
        );
    }

    /**
     * @dev Update the mapping between token on this blockchain and token on another blockchain.
     *
     * Requirements:
     * - the caller must have the `OPERATOR_ROLE`.
     *
     * @param _srcToken             Address of contract on this blockchain.
     * @param _destBcId             Blockchain ID where the corresponding contract resides.
     * @param _destToken            Address of contract on the other blockchain.
     */
    function updateTokenMapping(
        address _srcToken,
        uint256 _destBcId,
        address _destToken
    ) external onlyRole(OPERATOR_ROLE) {
        _validate(_tokenExists(_srcToken), "POSI Bridge: token not configured");
        _updateContractMapping(_srcToken, _destBcId, _destToken);
    }

    /**
     * Connect this POSI Bridge contract to an POSI Bridge contract on another blockchain.
     *
     * Requirements:
     * - the caller must have the `OPERATOR_ROLE`.
     *
     * @param _destBcId            Blockchain ID where the corresponding bridge contract resides.
     * @param _destBridge          Address of Bridge contract on other blockchain.
     */
    function updateBridgeMapping(
        uint256 _destBcId,
        address _destBridge
    ) external onlyRole(OPERATOR_ROLE) {
        remoteBridges[_destBcId] = _destBridge;
    }

    /**
     * Update this bridge to use new implementation of Simple Cross-Chain Control
     *
     * Requirements:
     * - the caller must have the `OPERATOR_ROLE`.
     *
     * @param _crossChainControl          Address of simple cross-chain control implementation
     */
    function updateCrossChainControl(
        address _crossChainControl
    ) external onlyRole(OPERATOR_ROLE) {
        crossChainControl = ICrossChainFunctionCall(_crossChainControl);
    }

    /**
     * Transfer any amount of any to anyone. This is needed to provide refunds to
     * customers who have had failed transactions where the token transfer occurred on this
     * blockchain, but did not happen on the destination blockchain.
     *
     * This function needs to be used with extreme caution. A system with
     * users' funds escrowed into this contact while they are used on a rollup
     * or sidechain needs to be kept in perfect balance. That is, the number of
     * escrowed tokens must match the number of tokens on other blockchains.
     *
     * Requirements:
     * - the caller must have the `REFUNDER_ROLE`.
     *
     * @param _token    Token to transfer.
     * @param _recipient        Address to transfer the tokens to.
     * @param _amount           Number of tokens to transfer.
     */
    function refund(
        address _token,
        address _recipient,
        uint256 _amount
    ) external onlyRole(REFUNDER_ROLE) {
        //        _amount = _transferOrMint(_token, _recipient, _amount);
        //        emit Refunded(_token, _recipient, _amount);
    }

    /**
     * Transfer all fee reserved for specific token to the fee collector.
     *
     * Requirements:
     * - the caller must have the `FEE_COLLECTOR_ROLE`.
     *
     * @param _token    Token to transfer.
     * @param _recipient        Address to transfer the tokens to.
     */
    function withdrawFee(
        address _token,
        address _recipient
    ) external onlyRole(FEE_COLLECTOR_ROLE) {
        uint256 amount = feeReserves[_token];
        feeReserves[_token] = 0;

        _withdraw(_token, _recipient, amount);
        emit FeeWithdrawn(_token, _recipient, amount);
    }

    // Convert 10^18 ---> 10^decimals
    function adjustWeiToTokenDecimal(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        uint256 fromDecimal = tokenDecimals[_token];
        uint256 toDecimal = 18;
        return _amount.mul(10 ** fromDecimal).div(10 ** toDecimal);
    }

    // Convert 10^decimals ---> 10^18
    function adjustTokenToWeiDecimal(
        address _token,
        uint256 _amount
    ) public view returns (uint256) {
        uint256 fromDecimal = 18;
        uint256 toDecimal = tokenDecimals[_token];
        return _amount.mul(10 ** fromDecimal).div(10 ** toDecimal);
    }

    // ***************************************************************************
    // ******* Internal below here ***********************************************
    // ***************************************************************************
    /**
     * @dev Mass Conservation: Transfer tokens that are owned by this contract to a recipient.
     * OR
     * Minting Burning: Mint token and assign them to a recipient.
     *
     * NOTE: The calls to the contracts are not wrapped. If they revert, the
     * entire call will revert. This will allow the user to see the revert message
     * from the contract. This will hopefully make it easier for a user to
     * debug the issue.
     *
     * @param _token      contract of the token being transferred or minted.
     * @param _recipient          Account to transfer ownership of the tokens to.
     * @param _amount             The number of tokens to be transferred.
     */
    function _transferOrMint(
        address _token,
        address _recipient,
        uint256 _amount
    ) private {
        _amount = adjustWeiToTokenDecimal(_token, _amount);
        if (
            tokenProcessMethods[_token] == TokenProcessMethod.MASS_CONSERVATION
        ) {
            _transferOut(_token, _recipient, _amount);
        } else {
            ERC20PresetMinterPauserUpgradeable(_token).mint(
                _recipient,
                _amount
            );
        }
    }

    /**
     * @dev Mass Conservation: TransferFrom tokens from a spender to this contract.
     * OR
     * Minting Burning: BurnFrom a spender's tokens.
     *
     * NOTE: The calls to the contracts are not wrapped. If they revert, the
     * entire call will revert. This will allow the user to see the revert message
     * from the contract. This will hopefully make it easier for a user to
     * debug the issue.
     *
     * @param _token              contract of the token being transferred or burned.
     * @param _spender            Account to transfer ownership of the tokens from.
     * @param _amount             The number of tokens to be transferred.
     */
    function _transferOrBurn(
        address _token,
        address _spender,
        uint256 _amount
    ) private {
        _amount = adjustWeiToTokenDecimal(_token, _amount);
        if (
            tokenProcessMethods[_token] == TokenProcessMethod.MASS_CONSERVATION
        ) {
            _transferIn(_token, _spender, _amount);
        } else {
            ERC20PresetMinterPauserUpgradeable(_token).burnFrom(
                _spender,
                _amount
            );
        }
    }

    function _increaseFeeReserves(
        address _token,
        uint256 _amount
    ) internal override {
        feeReserves[_token] += _amount;
        emit FeeCollected(_token, _amount);
    }

    function _tokenExists(address _token) private view returns (bool) {
        return tokenProcessMethods[_token] != TokenProcessMethod.NONE;
    }

    function _setTokenConfig(
        address _token,
        uint256 _decimals,
        uint256 _minTransferAmount,
        uint256 _feePercentage,
        uint256 _feeFlatAmount,
        uint256 _maxFeeAmount,
        TokenProcessMethod _processMethod,
        CollectFeeMethod _collectFeeMethod
    ) private {
        tokenDecimals[_token] = _decimals;
        tokenMinimumTransferAmount[_token] = _minTransferAmount;
        tokenFeePercentage[_token] = _feePercentage;
        tokenFeeFlatAmount[_token] = _feeFlatAmount;
        tokenMaxFeeAmount[_token] = _maxFeeAmount;

        tokenProcessMethods[_token] = _processMethod;
        _tokenCollectFeeMethod[_token] = _collectFeeMethod;

        emit TokenConfigUpdated(
            _token,
            _decimals,
            _minTransferAmount,
            _processMethod,
            _collectFeeMethod
        );
    }

    function _updateContractMapping(
        address _srcToken,
        uint256 _destBcId,
        address _destToken
    ) private {
        tokenAddressMapping[_srcToken][_destBcId] = _destToken;
        emit TokenMappingUpdated(_srcToken, _destBcId, _destToken);
    }

    function _validate(bool _condition, string memory _errorMsg) private pure {
        require(_condition, _errorMsg);
    }

    receive() external payable {}
}

