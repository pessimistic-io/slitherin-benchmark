import "./S4Proxy.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManagerStrategy.sol";
import "./ISwapRouter.sol";
import "./IWETH.sol";
import "./IFees.sol";

pragma solidity ^0.8.17;

// SPDX-License-Identifier: MIT

contract S4Strategy {
    address swapRouter;
    address feeContract;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address uniV2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address uniV3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nfpm = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    constructor(address swapRouter_, address feeContract_) {
        swapRouter = swapRouter_;
        feeContract = feeContract_;
    }

    uint256 constant public strategyId = 13;

    bytes32 constant onERC721ReceivedResponse =
        keccak256("onERC721Received(address,address,uint256,bytes)");

    //mappings

    //mapping of user address to proxy contract
    //user address => proxy contract
    mapping(address => address) public depositors;

    //mapping of user's v3PositionNft
    //assumption is made that nftId 0 will never exist
    //user => token0 => token1 => poolFee => nftId
    mapping(address => mapping(address => mapping(address => mapping(uint24 => uint256))))
        public v3PositionNft;

    //events
    event Deposit(address depositor, address tokenIn, uint256 amountIn); //, address poolAddress, uint poolFee);
    event Withdraw(
        address depositor,
        address tokenOut,
        uint256 amount,
        uint256 fee
    );
    event Claim(address depositor, address tokenOut, uint256 amount);

    //modifiers
    modifier whitelistedToken(address token) {
        require(
            IFees(feeContract).whitelistedDepositCurrencies(strategyId, token),
            "whitelistedToken: invalid token"
        );
        _;
    }

    //V3 functions
    //getter for v3 position
    function getV3Position(uint256 nftId)
        public
        view
        returns (
            //0: nonce
            uint96,
            //1: operator
            address,
            //2: token0
            address,
            //3: token1
            address,
            //4: fee
            uint24,
            //5:tickLower
            int24,
            //6:tickUpper
            int24,
            //7:liquidity (@dev current deposit)
            uint128,
            //8:feeGrowthInside0LastX128
            uint256,
            //9:feeGrowthInside1LastX128
            uint256,
            //10:tokensOwed0 (@dev avaliable to claim)
            uint128,
            //11:tokensOwed1 (@dev avaliable to claim)
            uint128
        )
    {
        return INonfungiblePositionManagerStrategy(nfpm).positions(nftId);
    }

    //getter for v3 pool data given poolAddress
    function getV3PoolData(address poolAddress)
        public
        view
        returns (
            address,
            address,
            uint256
        )
    {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        return (pool.token0(), pool.token1(), pool.fee());
    }

    //getter for v3 PoolAddress give tokens and fees
    function getV3PoolAddress(
        address token0,
        address token1,
        uint24 fee
    ) public view returns (address) {
        return IUniswapV3Factory(uniV3Factory).getPool(token0, token1, fee);
    }

    //getter for v3 position NFTs
    function getV3PositionNft(
        address user,
        address token0,
        address token1,
        uint24 poolFee
    )
        public
        view
        returns (
            address,
            address,
            uint256
        )
    {
        address _token0 = token0;
        address _token1 = token1;
        uint256 nftId = v3PositionNft[user][token0][token1][poolFee];
        if (nftId == 0) {
            _token0 = token1;
            _token1 = token0;
            nftId = v3PositionNft[user][token1][token0][poolFee];
        }
        return (_token0, _token1, nftId);
    }

    //withdraw position NFT to user
    function withdrawV3PositionNft(
        address token0,
        address token1,
        uint24 poolFee,
        uint256 nftId
    ) external {
        //delete nft form mapping
        v3PositionNft[msg.sender][token0][token1][poolFee] = 0;
        //we use the proxy map to gatekeep the rightful nft owner
        S4Proxy(depositors[msg.sender]).withdrawV3Nft(nftId);
    }

    //updates the liquidity band
    //@dev this call is extremely expensive
    //the position is withdrawn, nft burnt and reminted with redefined liquidity band
    function updateV3Position(
        address token0,
        address token1,
        uint24 poolFee,
        int24 tickLower,
        int24 tickUpper
    ) external {
        uint256 nftId;
        (token0, token1, nftId) = getV3PositionNft(
            msg.sender,
            token0,
            token1,
            poolFee
        );
        nftId = S4Proxy(depositors[msg.sender]).updateV3(
            nftId,
            tickLower,
            tickUpper
        );
        //update mapping with new nft
        v3PositionNft[msg.sender][token0][token1][poolFee] = nftId;
    }

    //allows user to claim fees
    //pass in address(0) to receive ETH
    //claim only avaliable on uniV3
    //we force claim the maximum possible amount for both tokens
    function claimV3(
        address token0,
        address token1,
        uint256 nftId,
        address tokenOut,
        uint256 amountOutMin
    ) external whitelistedToken(tokenOut) {
        uint256 result;
        address _tokenOut = tokenOut == address(0) ? wethAddress : tokenOut;
        (uint256 amountA, uint256 amountB) = S4Proxy(depositors[msg.sender])
            .claimV3(nftId, address(this));
        result = _swapTwoToOne(token0, token1, amountA, amountB, _tokenOut);
        require(result >= amountOutMin, "claim: amountOutMin not met");
        _sendToken(tokenOut, msg.sender, result);
        emit Claim(msg.sender, tokenOut, result);
    }

    //V2 Functions
    //getter for v2 pools
    function getV2PoolData(address poolAddress)
        public
        view
        returns (address, address)
    {
        IUniswapV2Pair pool = IUniswapV2Pair(poolAddress);
        return (pool.token0(), pool.token1());
    }

    function getV2PoolAddress(address token0, address token1)
        public
        view
        returns (address)
    {
        return IUniswapV2Factory(uniV2Factory).getPair(token0, token1);
    }

    //@dev pass address(0) for eth
    function depositToken(
        address tokenIn,
        address poolAddress,
        uint256 amount,
        uint256 token0MinOut,
        uint256 token1MinOut,
        bytes calldata params
    ) public payable whitelistedToken(tokenIn) {
        require(
            IFees(feeContract).depositStatus(strategyId),
            "depositToken: depositsStopped"
        );
        address proxy;
        address _tokenIn = tokenIn;
        if (tokenIn == address(0) || msg.value > 0) {
            (bool success, ) = payable(wethAddress).call{value: msg.value}("");
            require(success);
            amount = msg.value;
            _tokenIn = wethAddress;
        } else {
            IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);
        }
        //Check if proxy exists, else mint
        if (depositors[msg.sender] == address(0)) {
            S4Proxy newProxy = new S4Proxy(msg.sender);
            proxy = address(newProxy);
            depositors[msg.sender] = proxy;
        } else {
            proxy = depositors[msg.sender];
        }
        IUniswapV2Pair pool = IUniswapV2Pair(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        address factory = pool.factory();
        uint256 half = amount / 2;
        uint256 token0Amt = half;
        uint256 token1Amt = half;
        //tickLower & tickUpper ignored for v2
        //tickLower & tickUpper will be the full range if 0 is passed
        if (_tokenIn != token0) {
            //swap half for token0 to proxy
            IERC20(_tokenIn).approve(swapRouter, half);
            token0Amt = ISwapRouter(swapRouter).swapTokenForToken(
                _tokenIn,
                token0,
                half,
                token0MinOut,
                address(this)
            );
        }
        if (_tokenIn != token1) {
            //swap half for token1 to proxy
            IERC20(_tokenIn).approve(swapRouter, half);
            token1Amt = ISwapRouter(swapRouter).swapTokenForToken(
                _tokenIn,
                token1,
                half,
                token1MinOut,
                address(this)
            );
        }
        IERC20(token0).transfer(proxy, token0Amt);
        IERC20(token1).transfer(proxy, token1Amt);
        if (factory == uniV3Factory) {
            //v3 deposit
            (int24 tickLower, int24 tickUpper) = abi.decode(
                params,
                (int24, int24)
            );
            //check if user has existing nft
            //returns 0 if no existing nft
            uint24 poolFee = IUniswapV3Pool(poolAddress).fee();
            uint256 nftId = v3PositionNft[msg.sender][token0][token1][poolFee];
            //reuse token0Amt, token1Amt
            //minting returns nftId > 0
            //increaseLiquidityPosition returns nftId 0
            (nftId, token0Amt, token1Amt) = S4Proxy(depositors[msg.sender])
                .depositV3(
                    token0,
                    token1,
                    token0Amt,
                    token1Amt,
                    tickLower,
                    tickUpper,
                    poolFee,
                    nftId
                );
            if (nftId > 0) {
                v3PositionNft[msg.sender][token0][token1][poolFee] = nftId;
            }
        } else {
            //v2 deposit
            //reuse token0Amt, token1Amt
            (token0Amt, token1Amt) = S4Proxy(depositors[msg.sender]).depositV2(
                token0,
                token1,
                token0Amt,
                token1Amt
            );
        }
        //convert remainder back to original asset and return to user
        uint256 remainder;
        if (token0Amt > 0) {
            IERC20(token0).approve(swapRouter, token0Amt);
            remainder += ISwapRouter(swapRouter).swapTokenForToken(
                token0,
                _tokenIn,
                token0Amt,
                0,
                _tokenIn != address(0) ? msg.sender : address(this)
            );
        }
        if (token1Amt > 0) {
            IERC20(token1).approve(swapRouter, token1Amt);
            remainder += ISwapRouter(swapRouter).swapTokenForToken(
                token1,
                _tokenIn,
                token1Amt,
                0,
                _tokenIn != address(0) ? msg.sender : address(this)
            );
        }
        //router send tokens direct to user
        //only native eth needs to be converted before sending
        if (tokenIn == address(0) && remainder > 0) {
            _sendToken(address(0), msg.sender, remainder);
        }
        emit Deposit(msg.sender, tokenIn, amount);
    }

    //@dev pass address(0) for ETH
    function withdrawToken(
        address tokenOut,
        address poolAddress,
        uint128 amount,
        uint256 minAmountOut,
        address feeToken
    ) public whitelistedToken(tokenOut) returns (uint256) {
        IUniswapV2Pair pool = IUniswapV2Pair(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        address factory = pool.factory();
        address proxy = depositors[msg.sender];
        //amount of token0 received
        uint256 amountA;
        //amount of token1 received
        uint256 amountB;

        uint256 result;

        address _tokenOut = tokenOut == address(0) ? wethAddress : tokenOut;

        if (factory == uniV3Factory) {
            //We ignore the nft transfer to save gas
            //The proxy contract will hold the position NFT by default unless withdraw requested by user
            uint24 poolFee = IUniswapV3Pool(poolAddress).fee();
            (, , uint256 nftId) = getV3PositionNft(
                msg.sender,
                token0,
                token1,
                poolFee
            );
            (amountA, amountB) = S4Proxy(depositors[msg.sender]).withdrawV3(
                nftId,
                amount,
                address(this)
            );
        } else {
            IERC20(poolAddress).transferFrom(msg.sender, proxy, amount);
            (amountA, amountB) = S4Proxy(depositors[msg.sender]).withdrawV2(
                token0,
                token1,
                poolAddress,
                amount
            );
        }

        result = _swapTwoToOne(token0, token1, amountA, amountB, _tokenOut);
        require(result >= minAmountOut, "withdrawToken: minAmountOut not met");
        //transfer fee to feeCollector
        uint256 fee = ((
            IFees(feeContract).calcFee(
                strategyId,
                msg.sender,
                feeToken == address(0) ? tokenOut : feeToken
            )
        ) * result) / 1000;

        //Return token to sender
        _sendToken(tokenOut, msg.sender, result - fee);
        return result;
    }

    //swap multiple tokens to one
    function _swapTwoToOne(
        address token0,
        address token1,
        uint256 amountA,
        uint256 amountB,
        address _tokenOut
    ) internal returns (uint256) {
        ISwapRouter router = ISwapRouter(swapRouter);
        //optimistically assume result
        uint256 result = amountA + amountB;
        if (_tokenOut != token0 && amountA > 0) {
            //deduct incorrect amount
            result -= amountA;
            IERC20(token0).approve(swapRouter, amountA);
            //swap and add correct amount to result
            result += router.swapTokenForToken(
                token0,
                _tokenOut,
                amountA,
                1,
                address(this)
            );
        }
        if (_tokenOut != token1 && amountB > 0) {
            //deduct incorrect amount
            result -= amountB;
            IERC20(token1).approve(swapRouter, amountB);
            //swap and add correct amount to result
            result += router.swapTokenForToken(
                token1,
                _tokenOut,
                amountB,
                1,
                address(this)
            );
        }
        return result;
    }

    //internal functions
    function _sendToken(
        address tokenOut,
        address to,
        uint256 amount
    ) internal {
        if (tokenOut != address(0)) {
            IERC20(tokenOut).transfer(to, amount);
        } else {
            (bool sent, ) = payable(to).call{value: amount}("");
            require(sent, "_sendToken: send ETH fail");
        }
    }

    //hook called when nft is transferred to contract
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        require(
            INonfungiblePositionManagerStrategy(nfpm).ownerOf(tokenId) ==
                address(this),
            "S4Strategy: Invalid NFT"
        );
        require(depositors[from] != address(0), "S4Strategy: No Proxy");
        //add position nft to mapping
        (
            ,
            ,
            address token0,
            address token1,
            uint24 poolFee,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = getV3Position(tokenId);
        require(
            v3PositionNft[from][token0][token1][poolFee] == 0,
            "S4Strategy: Position already exists"
        );
        v3PositionNft[from][token0][token1][poolFee] = tokenId;
        bytes memory tokenData = abi.encode(poolFee, liquidity, token0, token1);
        INonfungiblePositionManagerStrategy(nfpm).safeTransferFrom(
            address(this),
            depositors[from],
            tokenId,
            tokenData
        );
        return bytes4(onERC721ReceivedResponse);
    }
}

