// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

// import "./base/Multicall.sol";
import "./ISwapRouter.sol";
import "./INFT.sol";
import "./ISubscription.sol";
import "./IPost.sol";

import "./TransferHelper.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./AggregatorV3Interface.sol";


//import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Operator is Ownable{
    ISwapRouter public constant swapRouter =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public immutable WETH9;

    AggregatorV3Interface public priceFeed;

    /// @dev payment accepted usd ERC20 (USDC|USDT)
    mapping(address => bool) public usdTokens;

    /// @dev  nft contract
    address public subscriptionNft;
    address public postNft;
    /// @dev
    address public feeTo;

    uint256 public FEE_SUBSCRIBE = 80; //8%
    //uint256 public FEE_SUBSCRIBE_TX = 30;//
    uint256 public ROYALTY = 25; //2.5%
    uint256 public FEE_TX = 30;

    bool public mintPause;
    bool public locked;
    bool private _swapSwitch;
    //first indexed sender
    event MintSubscription(
        address indexed sender,
        address author,
        uint256 tokenId,
        uint128 start,
        uint128 expire,
        uint256 price
    );
    event MintSubscriptionETH(
        address indexed sender,
        address author,
        uint256 tokenId,
        uint128 start,
        uint128 expire,
        uint256 price,
        uint256 priceETH
    );
    event BuySubscription(
        address indexed sender,
        address oldOwner,
        uint256 tokenId,
        uint256 amountIn
    );
    event BuySubscriptionETH(
        address indexed sender,
        address oldOwner,
        uint256 tokenId,
        uint256 priceETH
    );
    event MintPost(
        address indexed sender,
        uint256 tokenId,
        uint128 postId,
        uint256 price
    );
    event BuyPost(address indexed sender, address oldOwner, uint256 tokenId,uint256 amountIn);
    event BuyPostETH(address indexed sender, address oldOwner, uint256 tokenId,uint256 priceETH);
    event SendTips(address indexed sender, address to,uint256 fromId, uint256 tipsAmount);
    event SendTipsETH(address indexed sender, address to,uint256 fromId, uint256 tipsAmount,uint256 value);
 

    modifier mintAble() {
        require(!mintPause, "!mint"); //mint pause
        _;
    }
    modifier swapSwitch() {
        _swapSwitch = true;
        _;
        _swapSwitch = false;
    }

    modifier lock() {
        require(!locked, "lock");
        locked = true;
        _;
        locked = false;
    }

    constructor(address _WETH) {
        WETH9 = _WETH;
    }
 
   /*eth decimals 18*/
    function getOutputETHAmount(uint256 priceUsd) public view returns (uint256) {
        //price decimals 8
        /*uint80 roundID int price uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/
        (,int price ,,,) = priceFeed.latestRoundData();
        //1e8*(18 -priceUsd decimals) => 1e8*1e12 = 1e20
        return (priceUsd * 1e20)/uint256(price);
    }

    function setSubscriptionNft(address _subscription) external onlyOwner {
        subscriptionNft = _subscription;
    }
 
    function setPostNft(address _postNft) external onlyOwner {
        postNft = _postNft;
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        feeTo = _feeTo;
    }

    function setPriceFee(address _priceFeed) external onlyOwner {
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function setFeeTx(uint256 feeTx) external onlyOwner {
        FEE_TX = feeTx;
    }

    function setRoyalty(uint256 _royalty) external onlyOwner {
        ROYALTY = _royalty;
    }

    function setAcceptedUsdTokens(
        address _token,
        bool accepted
    ) external onlyOwner {
        usdTokens[_token] = accepted;

        // Approve the router to spend _token.
        TransferHelper.approve(_token, address(swapRouter), type(uint256).max);
    }

    //
    function approveSwapRouterToken(
        address _token,
        uint256 amount
    ) external onlyOwner {
         
        // Approve the router to spend _token.
        TransferHelper.approve(_token, address(swapRouter), amount);
    }

    function setFeeSubscribe(uint256 _percent) external onlyOwner {
        FEE_SUBSCRIBE = _percent;
    }

    function setMintAble(bool _pause) external onlyOwner {
        mintPause = _pause;
    }

    /// fee
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    ///subscribe pay with eth
    /// Called only when the user sets the payment method to ETH
    function mintSubscriptionETH(
        address to,
        address author,
        uint256 priceUsd,
        uint128 startAt,
        uint128 expireAt
    ) external payable mintAble returns (uint256 tokenId) {
        ///validate pay,
        // require(priceUsd >= 1e6, "p<1"); //price lt 1
        uint256 requireETH = getOutputETHAmount(priceUsd);
        require(requireETH <= msg.value, "eth insufficient"); 

        /// collect fee
        /// send to author
        (uint256 feeAmount, uint256 afterFeeAmount) = _feeSubscribeCalc(msg.value);
        payable(feeTo).transfer(feeAmount);
        payable(author).transfer(afterFeeAmount);

        tokenId = ISubscription(subscriptionNft).mint(
            to,
            author,
            startAt,
            expireAt
        );

        emit MintSubscriptionETH(to, author, tokenId, startAt, expireAt, priceUsd,msg.value);
    }

    ///should use multicall transfer eth to usd if necessary
    /// amountIn=price In usd 6 dicements
    /// tokenIn = USDC | USDT
    function mintSubscription(
        address to,
        address author,
        address tokenIn,
        uint256 price,
        uint128 startAt,
        uint128 expireAt
    ) external mintAble returns (uint256 tokenId) {
        if(price > 0){//0,free mint accepted

            ///validate pay,
            //require(price >= 1e6, "p<1"); //price lt 1
            require(usdTokens[tokenIn], "!usd"); //tokenIn not accepte
            //require(author!=msg.sender, "s=a");//sub-self occur erc20 transfrom STF,caller should check this

            /// collect fee
            /// direct transfer to author
            (uint256 feeAmount, uint256 afterFeeAmount) = _feeSubscribeCalc(price);
            TransferHelper.transferFrom(tokenIn, msg.sender, feeTo, feeAmount);
            TransferHelper.transferFrom(
                tokenIn,
                msg.sender,
                author,
                afterFeeAmount
            );
        }

        tokenId = ISubscription(subscriptionNft).mint(to, author, startAt, expireAt);

        emit MintSubscription(to, author, tokenId, startAt, expireAt, price);
    }

 

    /// must approve to spend the tokenIn,or transfer in the amount of tokenIn
    // must approval tokenId
    // check tokenId is for sale,price>0 ;set price 0 after buy
    // check amountIn >= price that retrieved  by tokenId
    // collect fee
    // transfer the left of tokenIn to owner,
    // transfer nft to sender
    function buySubscription(
        address to,
        address tokenIn,
        uint256 amountIn,
        uint256 tokenId
    ) external {
        //
        require(usdTokens[tokenIn], "!usd"); //tokenIn not accepted
        uint256 price = INFT(subscriptionNft).prices(tokenId);
        require(price > 0, "!sale"); //not for sale
        require(amountIn >= price, "amountIn insufficient");
        // no neccessary, if the amount insufficient occur transfer error 'stfc'
        //require(IERC20(tokenIn).balanceOf(msg.sender) >= amountIn,'balance insufficient');

        address owner = IERC721(subscriptionNft).ownerOf(tokenId);
        //
        (uint256 feeTx, uint256 afterFeeAmount) = _feeTxCalc(amountIn);

        TransferHelper.transferFrom(tokenIn, msg.sender, feeTo, feeTx);
        TransferHelper.transferFrom(tokenIn, msg.sender, owner, afterFeeAmount);

        _transferNFT(subscriptionNft, to, owner, tokenId);

        INFT(subscriptionNft).setPrice(tokenId, 0); //Take off the shelves

        emit BuySubscription(to, owner, tokenId,amountIn);
    }

 
    function buySubscriptionETH(address to,uint256 tokenId) external payable{
        //
        uint256 price = INFT(subscriptionNft).prices(tokenId);
        require(price > 0, "!sale"); //not for sale,or not exsist
        uint256 requireETH = getOutputETHAmount(price);
        require(msg.value >= requireETH, "eth insufficient"); //amountIn insufficient
        

        address owner = IERC721(subscriptionNft).ownerOf(tokenId);
        //
        (uint256 feeTx, uint256 afterFeeAmount) = _feeTxCalc(msg.value);
        payable(feeTo).transfer(feeTx);
        payable(owner).transfer(afterFeeAmount);


        _transferNFT(subscriptionNft, to, owner, tokenId);

        INFT(subscriptionNft).setPrice(tokenId, 0); //Take off the shelves

        emit BuySubscriptionETH(to, owner, tokenId,msg.value);
    }

    /// must approve to spend the tokenIn,or transfer in the amount of tokenIn
    // must approval tokenId
    // check amountIn >= price that retrieved  by tokenId
    // pay tax to author and collect fee
    // transfer the left of tokenIn to owner,
    // transfer nft to sender
    // take off the shelves
    function buyPost(
        address to,
        address tokenIn,
        uint256 amountIn,
        uint256 tokenId
    ) external lock {
        //
        require(usdTokens[tokenIn], "!usd"); //tokenIn not accepted
        // IPost.Meta memory meta = IPost(postNft).getMeta(tokenId);
        (address author,,) = IPost(postNft).metas(tokenId);
        uint256 price = INFT(postNft).prices(tokenId);
        require(price > 0, "!sale"); //not for sale
        require(amountIn >= price, "amountIn insufficient"); //
        //
        address owner = IERC721(postNft).ownerOf(tokenId);

        (uint256 royalty, uint256 taxTx, uint256 afterTaxAmount) = _taxCalc(
            amountIn
        );
        TransferHelper.transferFrom(
            tokenIn,
            msg.sender,
            author,
            royalty
        );
        TransferHelper.transferFrom(tokenIn, msg.sender, feeTo, taxTx);
        TransferHelper.transferFrom(tokenIn, msg.sender, owner, afterTaxAmount);

        _transferNFT(postNft, to, owner, tokenId);
        INFT(postNft).setPrice(tokenId, 0); //Take off the shelves

        emit BuyPost(to, owner, tokenId,amountIn);
    }


    function buyPostETH(uint256 tokenId) external payable lock {
                
        uint256 priceUsd = INFT(postNft).prices(tokenId);
        require(priceUsd > 0, "!sale"); //not for sale or not exists
        
        uint256 requireETH = getOutputETHAmount(priceUsd);
        require(requireETH <= msg.value, "eth insufficient"); 
        
        address owner = IERC721(postNft).ownerOf(tokenId);
        (address author,,) = IPost(postNft).metas(tokenId);

        (uint256 royalty, uint256 feeTx, uint256 afterTaxAmount) = _taxCalc(msg.value);
        payable(author).transfer(royalty);
        payable(feeTo).transfer(feeTx);
        payable(owner).transfer(afterTaxAmount);

        _transferNFT(postNft, msg.sender, owner, tokenId);
        INFT(postNft).setPrice(tokenId, 0); //Take off the shelves

        emit BuyPostETH(msg.sender, owner, tokenId,msg.value);
    }

    /// anyone can mint ,but only the author verification
    function mintPost(
        uint256 price,
        uint128 postId
    ) external mintAble returns (uint256 tokenId) {
        require(price >= 1e6, "p<1"); //usd lt 1

        tokenId = IPost(postNft).mint(msg.sender, postId, price);

        //a post mint that means up for sale ,so approval
        //INFT(postNft).operatorApprovalForAll(msg.sender);

        emit MintPost(msg.sender, tokenId, postId, price);
    }

    /// must approve to spend the tokenIn,or transfer in the amount of tokenIn
    // collect fee
    // transfer the left of tokenIn to toAccount
    function sendTips(
        address tokenIn,
        address to,
        uint256 fromId,
        uint256 tipsAmount
    ) external {
        require(tipsAmount>0, "tipsAmount=0"); 
        require(usdTokens[tokenIn], "!usd"); //tokenIn not accepted

        (uint256 feeTx, uint256 afterFeeAmount) = _feeTxCalc(tipsAmount);
        TransferHelper.transferFrom(tokenIn, msg.sender, feeTo, feeTx);
        TransferHelper.transferFrom(
            tokenIn,
            msg.sender,
            to,
            afterFeeAmount
        );
        //msg.sender might be this,by swapAndCall/multicall
        emit SendTips(tx.origin, to,fromId ,tipsAmount);
    }

    function sendTipsETH(address to,uint256 fromId,uint256 tipsAmount) external payable{
        //
        require(msg.value>0, "eth0");  
        uint256 requireETH = getOutputETHAmount(tipsAmount);
        require(requireETH <= msg.value, "eth insufficient"); 

        (uint256 feeAmount, uint256 afterFeeAmount) = _feeTxCalc(msg.value);
        payable(feeTo).transfer(feeAmount);
        payable(to).transfer(afterFeeAmount);
 

        emit SendTipsETH(tx.origin, to,fromId,tipsAmount, msg.value);
    }

    function _taxCalc(uint256 amountIn)
        private
        view
        returns (uint256 _royalty, uint256 feeTx, uint256 afterTaxAmount)
    {
        _royalty = (ROYALTY * amountIn) / 1000;
        feeTx = (FEE_TX * amountIn) / 1000;
        afterTaxAmount = amountIn - _royalty - feeTx;
    }

    function _feeTxCalc(
        uint256 amountIn
    ) private view returns (uint256 feeTx, uint256 afterFeeAmount) {
        feeTx = (FEE_TX * amountIn) / 1000;
        afterFeeAmount = amountIn - feeTx;
    }

    function _feeSubscribeCalc(
        uint256 amountIn
    ) private view returns (uint256 feeAmount, uint256 afterFeeAmount) {
        feeAmount = (FEE_SUBSCRIBE * amountIn) / 1000;
        afterFeeAmount = amountIn - feeAmount;
    }

    //swap recipient -> payment sender
    function _tokenSender() private view returns (address sender) {
        sender = _swapSwitch ? address(this) : msg.sender;
    }

    function _transferNFT(
        address nft,
        address to,
        address owner,
        uint256 tokenId
    ) private {
        INFT(nft).operatorApprovalForAll(owner);
        IERC721(nft).transferFrom(owner, to, tokenId);
    }

    ///  uint24 feeAmount = 10000;3000;500
    /// tokenIn tokenOut fee => pool
    /// tokenOut = usdERC20
    /// we dont use multicall from frontend to swap,so the user dont have to approve the usdERC20,ux better
    ///swap uniswap list token to usd by tokenIn/tokenOut(usd) pool,then mintXXX
    function swapAndCall(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 amountOut,
        uint24 feeAmount,
        bytes memory callData
    ) external payable {
      
        bool inputIsWETH9 =tokenIn == WETH9;

        if (inputIsWETH9) {
            require(msg.value > 0, "eth0");
            amountInMax = msg.value;
        }else{
            require(IERC20(tokenIn).balanceOf(msg.sender)>=amountInMax, "balance insufficient");
            TransferHelper.transferFrom(tokenIn, msg.sender, address(this), amountInMax);
            //TransferHelper.approve(tokenIn, swapRouter, amountInMax);
        }

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: feeAmount,
                recipient: address(this), //msg.sender,
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum: amountInMax,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        //amountIn = swapRouter.exactOutputSingle(params);
        uint256 amountIn = swapRouter.exactOutputSingle{value: msg.value}(params);

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        uint256 diffIn = amountInMax - amountIn;
        if (diffIn > 0) {
            if(inputIsWETH9){
                swapRouter.refundETH();
                // // refund leftover ETH to user
                TransferHelper.transferETH(msg.sender, diffIn); //msg.sender
            }else{
                TransferHelper.safeTransfer(tokenIn, msg.sender,  diffIn);
            }
        }

        (bool success, bytes memory result) = address(this).call(callData);

        if (!success) {
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

    }

    ///swap any uniswap list token to usd by tokenIn/middleToken../tokenOut pool,then mintXXX
    //tokenIn can't be WETH9
    // tokenOut is usdTokens
    // tokenIn = path.toAddress(0);
    function swapMultiAndCall(
        bytes memory path,
        address tokenIn,
        uint256 amountInMaximum,
        uint256 amountOut,
        bytes memory callData
    ) external {
        require(IERC20(tokenIn).balanceOf(msg.sender)>=amountInMaximum, "balance insufficient");
        TransferHelper.transferFrom(tokenIn, msg.sender, address(this), amountInMaximum);
        //TransferHelper.approve(tokenIn, swapRouter, amountInMax);
 
        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams({
                path:path,
                recipient: address(this),
                deadline: block.timestamp,
                amountOut: amountOut,
                amountInMaximum:amountInMaximum
            });

    
        uint256 amountIn = swapRouter.exactOutput(params);

        uint256 diffIn = amountInMaximum - amountIn;
        if (diffIn > 0) {
            TransferHelper.safeTransfer(tokenIn, msg.sender,  diffIn);
        }

        (bool success, bytes memory result) = address(this).call(callData);

        if (!success) {
            if (result.length < 68) revert();
            assembly {
                result := add(result, 0x04)
            }
            revert(abi.decode(result, (string)));
        }

    }

    //refundETH
    receive() external payable {}

    fallback() external payable {}
}

