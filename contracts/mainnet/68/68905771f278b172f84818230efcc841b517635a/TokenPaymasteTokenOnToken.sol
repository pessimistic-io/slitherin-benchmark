pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IForwarder.sol";
import "./BasePaymaster.sol";

import "./IUniswapV2Router02.sol";

/**
 * A Token-based paymaster.
 * - each request is paid for by the caller.
 * - acceptRelayedCall - verify the caller can pay for the request in tokens.
 * - preRelayedCall - pre-pay the maximum possible price for the tx
 * - postRelayedCall - refund the caller for the unused gas
 */
contract TokenPaymasterForTokenOnTokenSwap is BasePaymaster {
    using SafeMath for uint256;
    struct PreChargeData{
        address payer;
        uint256 tokenPreCharge;
        uint256 ethMaxCharge;
    }

    function versionPaymaster()
        external
        view
        virtual
        override
        returns (string memory)
    {
        return "2.2.3+opengsn.token.ipaymaster";
    }

    IUniswapV2Router02 private immutable _router;
    mapping(address => bool) private _isTokenWhitelisted;
    address private _paymentToken;
    uint256 private _fee;
    uint256 public minGas = 400000;
    address public target;
    uint256 public minBalance = 0.001 ether;
    uint256 public gasUsedByPost = 80000;

    constructor(
        address uniswapRouter,
        address forwarder,
        address paymentToken,
        uint256 fee,
        IRelayHub hub
    ) {
        _router = IUniswapV2Router02(uniswapRouter);
        _paymentToken = paymentToken;
        _fee = fee;
        setTrustedForwarder(forwarder);
        setRelayHub(hub);
    }

    function setMinBalance(uint256 _minBalance) external onlyOwner {
        require(_minBalance > 0, "Wrong min balance");
        minBalance = _minBalance;
    }

    function setPaymentToken(address paymentToken) external onlyOwner {
        require(paymentToken != address(0), "Wrong Payment Token");
        _paymentToken = paymentToken;
    }

    function getPaymentData() external view returns (address, uint256) {
        return (_paymentToken, _fee);
    }

    function setFee(uint256 fee) external onlyOwner {
        _fee = fee;
    }

    function whitelistToken(address token, bool whitelist) external onlyOwner {
        require(token != address(0), "Token address is 0");
        _isTokenWhitelisted[token] = whitelist;
    }

    function isTokenWhitelisted(address token) external view returns (bool) {
        return _isTokenWhitelisted[token];
    }

    function setGasUsedByPost(uint256 _gasUsedByPost) external onlyOwner {
        gasUsedByPost = _gasUsedByPost;
    }

    function setMinGas(uint256 _minGas) external onlyOwner {
        minGas = _minGas;
    }

    function setTarget(address _target) external onlyOwner {
        target = _target;
    }

    function setPostGasUsage(uint256 _gasUsedByPost) external onlyOwner {
        gasUsedByPost = _gasUsedByPost;
    }

    function getPayer(GsnTypes.RelayRequest calldata relayRequest)
        public
        view
        virtual
        returns (address)
    {
        (this);
        return relayRequest.request.from;
    }

    event Received(uint256 eth);

    receive() external payable override {
        emit Received(msg.value);
    }

    function _calculatePreCharge(
        address token,
        GsnTypes.RelayRequest calldata relayRequest,
        uint256 maxPossibleGas
    )
        internal
        view
        returns (
            PreChargeData memory prechargeInfo
        )
    {
        (token);
        prechargeInfo.payer = this.getPayer(relayRequest);
        prechargeInfo.ethMaxCharge = relayHub.calculateCharge(
            maxPossibleGas,
            relayRequest.relayData
        );
        prechargeInfo.ethMaxCharge += relayRequest.request.value;
        prechargeInfo.tokenPreCharge = _router.getAmountsOut(
            prechargeInfo.ethMaxCharge,
            _getPath(_router.WETH(), token)
        )[1];

        return prechargeInfo;
    }

    function _getPath(address token1, address token2)
        private
        pure
        returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = token1;
        path[1] = token2;
    }

    function getTokenToTokenOutput(uint256 amountIn, address[] memory path)
        public
        view
        returns (uint256)
    {
        uint256 amountOut = _router.getAmountsOut(amountIn, path)[1];
        return amountOut;
    }

    function preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata,
        bytes calldata,
        uint256 maxPossibleGas
    )
        external
        virtual
        override
        relayHubOnly
        returns (bytes memory context, bool revertOnRecipientRevert)
    {
        _verifyForwarder(relayRequest);

        IForwarder.ForwardRequest calldata request = relayRequest.request;

        require(request.to == target, "Unknown target");

        (address tokenIn, address tokenOut, uint256 amount) = abi.decode(
            relayRequest.request.data[4:],
            (address, address, uint256)
        );

        require(_isTokenWhitelisted[tokenIn], "Token not whitelisted");

        PreChargeData memory prechargeInfo = _calculatePreCharge(tokenOut, relayRequest, maxPossibleGas);

        IERC20 paymentToken = IERC20(_paymentToken);

        if (_paymentToken == tokenIn) {
            require(
                paymentToken.allowance(prechargeInfo.payer, target) >= _fee + amount,
                "Fee+amount: Not enough allowance"
            );
            require(
                paymentToken.balanceOf(prechargeInfo.payer) >= _fee + amount,
                "Fee+amount: Not enough balance"
            );
        } else {
            require(
                paymentToken.allowance(prechargeInfo.payer, target) >= _fee,
                "Fee: Not enough allowance"
            );
            require(
                paymentToken.balanceOf(prechargeInfo.payer) >= _fee,
                "Fee: Not enough balance"
            );

            IERC20 token = IERC20(tokenIn);
            require(
                token.allowance(prechargeInfo.payer, target) >= amount,
                "Not enough allowance"
            );
            require(
                token.balanceOf(prechargeInfo.payer) >= amount,
                "Not enough balance"
            );
        }
    
        address[] memory pathInOut = _getPath(tokenIn, tokenOut);
        uint256 tokenOutAmount = getTokenToTokenOutput(amount, pathInOut);

        address[] memory path = _getPath(tokenOut, _router.WETH());
        uint256 amountOut = getTokenToTokenOutput(tokenOutAmount, path);

        require(amountOut > prechargeInfo.ethMaxCharge, "Not enough to pay for tx");

        require(request.gas >= minGas, "Not enough gas");

        // token.transferFrom(payer, address(this), tokenPrecharge);
        return (abi.encode(prechargeInfo.payer, prechargeInfo.tokenPreCharge, tokenOut, amountOut), true);
    }

    function postRelayedCall(
        bytes calldata context,
        bool,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData
    ) external virtual override relayHubOnly {
        (address payer, uint256 tokenPrecharge, address tokenOut, ) = abi
            .decode(context, (address, uint256, address, uint256));
        _postRelayedCallInternal(
            payer,
            tokenPrecharge,        
            gasUseWithoutPost,
            relayData,
            tokenOut
        );
    }

    function _postRelayedCallInternal(
        address payer,
        uint256 ,
        uint256 gasUseWithoutPost,
        GsnTypes.RelayData calldata relayData,
        address tokenOut
    ) internal {
        uint256 ethActualCharge = relayHub.calculateCharge(
            gasUseWithoutPost.add(gasUsedByPost),
            relayData
        );
        uint256 tokenActualCharge = _router.getAmountsOut(
            ethActualCharge,
            _getPath(_router.WETH(), tokenOut)
        )[1];
        
        _depositProceedsToHub(ethActualCharge, tokenOut);
        _refundPayer(payer, tokenOut);

        emit TokensCharged(
            gasUseWithoutPost,
            gasUsedByPost,
            ethActualCharge,
            tokenActualCharge
        );
    }

    function _refundPayer(
        address payer,
        address token
    ) private {
        require(IERC20(token).transfer(payer, IERC20(token).balanceOf(address(this))), "failed refund");
    }

    function _depositProceedsToHub(uint256 ethActualCharge, address tokenOut)
        private
    {   
        IERC20(tokenOut).approve(address(_router), type(uint256).max);
        _router.swapTokensForExactETH(
            ethActualCharge,
            type(uint256).max,
            _getPath(tokenOut, _router.WETH()),
            address(this),
            block.timestamp + 60 * 15
        );

        relayHub.depositFor{value: ethActualCharge}(address(this));
    }

    event TokensCharged(
        uint256 gasUseWithoutPost,
        uint256 gasJustPost,
        uint256 ethActualCharge,
        uint256 tokenActualCharge
    );
}

