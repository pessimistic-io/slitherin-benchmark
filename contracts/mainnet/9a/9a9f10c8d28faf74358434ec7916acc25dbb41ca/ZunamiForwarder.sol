//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./SafeERC20.sol";

import "./IStargateRouter.sol";
import "./IZunami.sol";
import "./ICurvePool.sol";

import "./LzApp.sol";

contract ZunamiForwarder is LzApp {
    using SafeERC20 for IERC20Metadata;

    bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');

    enum MessageType {
        Deposit,
        Withdrawal
    }

    IZunami public immutable zunami;
    ICurvePool public immutable curveExchange;
    IStargateRouter public immutable stargateRouter;

    uint8 public constant POOL_ASSETS = 3;

    int128 public constant DAI_TOKEN_ID = 0;
    int128 public constant USDC_TOKEN_ID = 1;
    uint128 public constant USDT_TOKEN_ID = 2;

    uint256 public constant SG_SLIPPAGE_DIVIDER = 10000;

    uint256 public stargateSlippage = 50;
    IERC20Metadata[POOL_ASSETS] public tokens;
    uint256 public immutable tokenPoolId;

    uint256 public storedLpShares;

    uint256 public currentDepositId;
    uint256 public currentDepositAmount;

    uint256 public currentWithdrawalId;
    uint256 public currentWithdrawalAmount;

    uint16 public gatewayChainId;
    address public gatewayAddress;
    uint256 public gatewayTokenPoolId;

    uint256 public crossDepositGas = 50000;
    uint256 public crossWithdrawalGas = 50000;
    uint256 public crossProvisionGas = 40000;

    event InitiatedCrossDeposit(uint256 indexed id, uint256 tokenId, uint256 tokenAmount);
    event CreatedPendingDeposit(uint256 indexed id, uint256 tokenId, uint256 tokenAmount);
    event Deposited(uint256 indexed id, uint256 lpShares);

    event CreatedPendingWithdrawal(uint256 indexed id, uint256 lpShares);
    event Withdrawn(uint256 indexed id, uint256 tokenId, uint256 tokenAmount);

    event SetGatewayParams(
        uint256 chainId,
        address gateway,
        uint256 tokenPoolId
    );

    event SetStargateSlippage(
        uint256 slippage
    );

    event SetLayerZeroMessagesGas(
        uint256 crossDepositGas,
        uint256 crossWithdrawalGas,
        uint256 crossProvisionGas
    );

    constructor(
        IERC20Metadata[POOL_ASSETS] memory _tokens,
        uint256 _tokenPoolId,
        address _zunami,
        address _curveExchange,
        address _stargateRouter,
        address _layerZeroEndpoint
    ) public LzApp(_layerZeroEndpoint) {
        _setupRole(OPERATOR_ROLE, _msgSender());
        tokens = _tokens;
        tokenPoolId = _tokenPoolId;

        zunami = IZunami(_zunami);
        stargateRouter = IStargateRouter(_stargateRouter);

        curveExchange = ICurvePool(_curveExchange);
    }

    receive() external payable {}

    function setGatewayParams(
        uint16 _chainId,
        address _address,
        uint256 _tokenPoolId
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        gatewayChainId = _chainId;
        gatewayAddress = _address;
        gatewayTokenPoolId = _tokenPoolId;

        emit SetGatewayParams(_chainId, _address, _tokenPoolId);
    }

    function setStargateSlippage(
        uint16 _slippage
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_slippage <= SG_SLIPPAGE_DIVIDER,"Forwarder: wrong stargate slippage");
        stargateSlippage = _slippage;

        emit SetStargateSlippage(_slippage);
    }

    function setLayerZeroMessagesGas(
        uint256 _crossDepositGas,
        uint256 _crossWithdrawalGas,
        uint256 _crossProvisionGas
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        crossDepositGas = _crossDepositGas;
        crossWithdrawalGas = _crossWithdrawalGas;
        crossProvisionGas = _crossProvisionGas;
        emit SetLayerZeroMessagesGas(_crossDepositGas, _crossWithdrawalGas, _crossProvisionGas);
    }

    function _lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) internal override {
        require(_srcChainId == gatewayChainId, "Forwarder: wrong source chain id");

        // Receive request to withdrawal or deposit
        (uint8 messageType, uint256 messageId, uint256 tokenAmount, uint8 tokenDecimals) =
            abi.decode(_payload, (uint8, uint256, uint256, uint8));

        if(messageType == uint8(MessageType.Withdrawal)) {
            require(currentWithdrawalId == 0 && currentWithdrawalAmount == 0, "Forwarder: previous withdrawal existed");

            currentWithdrawalId = messageId;
            currentWithdrawalAmount = tokenAmount; //don't convert - zlp anf gzlp have same decimals

            // Delegate withdrawal request to Zunami
            uint256[POOL_ASSETS] memory tokenAmounts;
            zunami.delegateWithdrawal(tokenAmount, tokenAmounts);

            emit CreatedPendingWithdrawal(currentWithdrawalId, tokenAmount);
        } else if(messageType == uint8(MessageType.Deposit)) {
            require(currentDepositId == 0 && currentDepositAmount == 0, "Forwarder: previous deposit existed");

            currentDepositId = messageId;
            currentDepositAmount = convertDecimals(tokenAmount, tokenDecimals, IERC20Metadata(tokens[USDT_TOKEN_ID]).decimals());

            emit InitiatedCrossDeposit(messageId, USDT_TOKEN_ID, currentDepositAmount);
        }
    }

    function delegateCrossDeposit()
    external
    onlyRole(OPERATOR_ROLE)
    {
        require(currentDepositId != 0 && currentDepositAmount != 0, "Forwarder: deposit wasn't initiated");
        uint256 realDepositAmount = IERC20Metadata(tokens[USDT_TOKEN_ID]).balanceOf(address(this));
        require( realDepositAmount >=
            currentDepositAmount * (SG_SLIPPAGE_DIVIDER - stargateSlippage) / SG_SLIPPAGE_DIVIDER,
            "Forwarder: not enough provision"
        );

        // delegate deposit to Zunami
        IERC20Metadata(tokens[USDT_TOKEN_ID]).safeIncreaseAllowance(address(zunami), realDepositAmount);

        uint256[3] memory amounts;
        amounts[uint256(USDT_TOKEN_ID)] = realDepositAmount;
        zunami.delegateDeposit(amounts);

        emit CreatedPendingDeposit(currentDepositId, USDT_TOKEN_ID, realDepositAmount);
    }

    function completeCrossDeposit()
    external
    payable
    onlyRole(OPERATOR_ROLE)
    {
        require(currentDepositId != 0, "Forwarder: deposit not processing");

        uint256 lpShares = IERC20Metadata(address(zunami)).balanceOf(address(this)) - storedLpShares;
        // 0/ wait until receive ZLP tokens back
        require(lpShares > 0, "Forwarder: deposit wasn't completed at Zunami");

        storedLpShares += lpShares;

        // send layer zero message to Gateway with LP shares deposit amount
        bytes memory payload = abi.encode(uint8(MessageType.Deposit), currentDepositId, lpShares, 18);
        _lzSend(gatewayChainId, payload, crossDepositGas);

        emit Deposited(currentDepositId, lpShares);

        delete currentDepositId;
        delete currentDepositAmount;
    }

    function completeCrossWithdrawal()
    external
    payable
    onlyRole(OPERATOR_ROLE)
    {
        // 0/ wait to receive stables from Zunami
        require(currentWithdrawalId != 0 && currentWithdrawalAmount != 0, "Forwarder: withdrawal is not processing");

        // 1/ exchange DAI and USDC to USDT
        exchangeOtherTokenToUSDT(DAI_TOKEN_ID);
        exchangeOtherTokenToUSDT(USDC_TOKEN_ID);

        // 2/ send USDT by startgate to gateway
        uint256 tokenTotalAmount = tokens[USDT_TOKEN_ID].balanceOf(address(this));

        tokens[USDT_TOKEN_ID].safeIncreaseAllowance(address(stargateRouter), tokenTotalAmount);

        stargateRouter.swap{value:address(this).balance}(
            gatewayChainId,                                     // LayerZero chainId
            tokenPoolId,                                        // source pool id
            gatewayTokenPoolId,                                 // dest pool id
            payable(address(this)),                              // refund address. extra gas (if any) is returned to this address
            tokenTotalAmount,                                   // quantity to swap
            tokenTotalAmount * (SG_SLIPPAGE_DIVIDER - stargateSlippage) / SG_SLIPPAGE_DIVIDER, // the min qty you would accept on the destination
            IStargateRouter.lzTxObj(crossProvisionGas, 0, "0x"),            // 0 additional gasLimit increase, 0 airdrop, at 0x address
            abi.encodePacked(gatewayAddress),                   // the address to send the tokens to on the destination
            ""               // bytes param, if you wish to send additional payload you can abi.encode() them here
        );

        bytes memory payload = abi.encode(uint8(MessageType.Withdrawal), currentWithdrawalId, tokenTotalAmount, tokens[USDT_TOKEN_ID].decimals());
        _lzSend(gatewayChainId, payload, crossWithdrawalGas);

        storedLpShares -= currentWithdrawalAmount;
        require( IERC20Metadata(address(zunami)).balanceOf(address(this)) == storedLpShares, "Forwarder: withdrawal wasn't completed in Zunami");

        emit Withdrawn(currentWithdrawalId, USDT_TOKEN_ID, tokenTotalAmount);

        delete currentWithdrawalId;
        delete currentWithdrawalAmount;
    }

    function exchangeOtherTokenToUSDT(int128 tokenId) internal {
        uint256 tokenBalance = tokens[uint128(tokenId)].balanceOf(address(this));
        if(tokenBalance > 0) {
            tokens[uint128(tokenId)].safeIncreaseAllowance(address(curveExchange), tokenBalance);
            curveExchange.exchange(tokenId, int128(USDT_TOKEN_ID), tokenBalance, 0);
        }
    }

    /**
     * @dev governance can withdraw all stuck funds in emergency case
     * @param _token - IERC20Metadata token that should be fully withdraw from Zunami
     */
    function withdrawStuckToken(IERC20Metadata _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokenBalance = _token.balanceOf(address(this));
        if (tokenBalance > 0) {
            _token.safeTransfer(_msgSender(), tokenBalance);
        }
    }

    function withdrawStuckNative() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            payable(_msgSender()).transfer(balance);
        }
    }

    function convertDecimals(
        uint256 _value,
        uint8 _decimalsFrom,
        uint8 _decimalsTo
    ) public view returns (uint256) { // pure
        if(_decimalsFrom == _decimalsTo) return _value;
        if(_decimalsFrom > _decimalsTo) return convertDownDecimals(_value, _decimalsFrom, _decimalsTo);
        return convertUpDecimals(_value, _decimalsFrom, _decimalsTo);
    }

    function convertUpDecimals(
        uint256 _value,
        uint8 _decimalsFrom,
        uint8 _decimalsTo
    ) public pure returns (uint256) {
        require(_decimalsFrom <= _decimalsTo, "BADDECIM");
        return _value * (10**(_decimalsTo - _decimalsFrom));
    }

    function convertDownDecimals(
        uint256 _value,
        uint8 _decimalsFrom,
        uint8 _decimalsTo
    ) public pure returns (uint256) {
        require(_decimalsFrom >= _decimalsTo, "BADDECIM");
        return _value / (10**(_decimalsFrom - _decimalsTo));
    }
}

