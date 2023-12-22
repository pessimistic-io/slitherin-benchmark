// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IInscription.sol";
import "./IInscriptionFactory.sol";
import "./INonfungiblePositionManager.sol";
import "./IWETH.sol";
import "./TransferHelper.sol";
import "./PriceFormat.sol";
import "./IUniswapV3Factory.sol";
import "./ICustomizedVesting.sol";

// This contract will be created while deploying
// The liquidity can not be removed
contract InitialFairOffering {
    int24 private constant MIN_TICK = -887272; // add liquidity with full range
    int24 private constant MAX_TICK = -MIN_TICK; // add liquidity with full range
    int24 public constant TICK_SPACING = 60; // Tick space is 60
    uint24 public constant UNISWAP_FEE = 3000;

    INonfungiblePositionManager public constant nonfungiblePositionManager =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);

    IUniswapV3Factory public uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    IWETH public weth;

    IInscriptionFactory public inscriptionFactory;

    bool public liquidityAdded = false;

    struct MintData {
        uint128 ethAmount; // eth payed by user(deduce commission)
        uint128 tokenAmount; // token minted by user
        uint128 tokenLiquidity; // token liquidity saved in this contract
    }

    mapping(address => MintData) public mintData;

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }
    mapping(uint => Deposit) public deposits; // uint - tokenId of liquidity NFT
    mapping(uint => uint) public tokenIds;
    uint public tokenIdCount;
    uint public totalBackToDeployAmount;
    uint public totalRefundedAmount;

    struct Position {
        uint96 nonce;
        address operator;
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint256 tokenId;
    }

    struct Pool {
        address pool;
        address token0;
        address token1;
        uint uintRate;
        uint160 sqrtPriceX96;
    }
    Pool public poolData;

    IInscriptionFactory.Token public token;

    event MintDeposit(
        address token,
        uint128 ethAmount,
        uint128 tokenAmount,
        uint128 tokenLiquidity
    );
    event Refund(
        address sender,
        uint128 etherAmount,
        uint128 senderToken,
        uint128 liquidityToken,
        uint16 refundFee
    );

    // This contract can be only created by InscriptionFactory contract
    constructor(address _inscriptionFactory, address _weth) {
        inscriptionFactory = IInscriptionFactory(_inscriptionFactory);
        weth = IWETH(_weth);
    }

    receive() external payable {
        // Change all received ETH to WETH
        if (msg.sender != address(weth))
            TransferHelper.safeTransferETH(address(weth), msg.value);
    }

    function initialize(IInscriptionFactory.Token memory _token) public {
        // Check if the deployer has sent the liquidity ferc20 tokens
        require(
            address(inscriptionFactory) == msg.sender,
            "Only inscription factory allowed"
        );
        require(_token.inscriptionId > 0, "token data wrong");
        token = _token;
        _initializePool(address(weth), _token.addr);
    }

    function _initializePool(
        address _weth,
        address _token
    )
        private
        returns (
            address _token0,
            address _token1,
            uint _uintRate,
            uint160 _sqrtPriceX96,
            address _pool
        )
    {
        _token0 = _token;
        _token1 = _weth;

        _uintRate = PriceFormat.getInitialRate(
            token.crowdFundingRate,
            token.liquidityEtherPercent,
            token.liquidityTokenPercent,
            token.limitPerMint
        ); // weth quantity per token
        require(_uintRate > 0, "uint rate zero");

        if (_token < _weth) {
            _sqrtPriceX96 = PriceFormat.priceToSqrtPriceX96(
                int(_uintRate),
                TICK_SPACING
            );
        } else {
            _token0 = _weth;
            _token1 = _token;
            _uintRate = 10 ** 36 / _uintRate; // token quantity per weth
            _sqrtPriceX96 = PriceFormat.priceToSqrtPriceX96(
                int(_uintRate),
                TICK_SPACING
            );
        }
        _pool = nonfungiblePositionManager.createAndInitializePoolIfNecessary(
            _token0,
            _token1,
            UNISWAP_FEE,
            _sqrtPriceX96
        );
        poolData = Pool(_pool, _token0, _token1, _uintRate, _sqrtPriceX96);
    }

    function addLiquidity(uint16 slippage) public {
        require(slippage >= 0 && slippage <= 10000, "slippage error");
        require(
            IInscription(token.addr).totalRollups() >= token.maxRollups,
            "mint not finished"
        );
        require(
            uniswapV3Factory.getPool(address(weth), token.addr, UNISWAP_FEE) >
                address(0x0),
            "Pool not exist, create pool in uniswapV3 manually"
        );
        require(token.liquidityEtherPercent > 0, "no liquidity add");
        uint256 totalTokenLiquidity = IInscription(token.addr).balanceOf(
            address(this)
        );
        require(totalTokenLiquidity > 0, "no token in fto contract");
        uint256 balanceOfWeth = IWETH(weth).balanceOf(address(this));
        require(balanceOfWeth > 0, "no eth in fto contract");

        // Send ether back to deployer, the eth liquidity is based on the balance of this contract. So, anyone can send eth to this contract
        uint256 backToDeployAmount = (balanceOfWeth *
            (10000 - token.liquidityEtherPercent)) / 10000;
        uint256 maxBackToDeployAmount = (token.maxRollups *
            (10000 - inscriptionFactory.fundingCommission()) *
            token.crowdFundingRate *
            (10000 - token.liquidityEtherPercent)) / 100000000;

        uint256 sum = totalBackToDeployAmount + backToDeployAmount;

        if (sum <= maxBackToDeployAmount) {
            weth.withdraw(backToDeployAmount); // Change WETH to ETH
            TransferHelper.safeTransferETH(token.deployer, backToDeployAmount);
            totalBackToDeployAmount += backToDeployAmount;
        } else {
            backToDeployAmount = 0;
        }

        liquidityAdded = true; // allow the transferring of token

        _mintNewPosition(
            balanceOfWeth - backToDeployAmount,
            totalTokenLiquidity, // ferc20 token amount
            MIN_TICK,
            MAX_TICK,
            slippage
        );
    }

    function refund() public {
        require(mintData[msg.sender].ethAmount > 0, "you have not mint");
        require(
            IInscription(token.addr).totalRollups() < token.maxRollups,
            "mint has finished"
        );

        if (
            token.isVesting &&
            token.customizedVestingContractAddress != address(0x0)
        ) {
            // standard fto mode
            ICustomizedVesting(token.customizedVestingContractAddress)
                .removeAllocation(msg.sender, mintData[msg.sender].tokenAmount);
        } else {
            // not fto mode
            // check balance and allowance of tokens, if the balance or allowance is smaller than the what he/she get while do mint, the refund fail
            require(
                IInscription(token.addr).balanceOf(msg.sender) >=
                    mintData[msg.sender].tokenAmount,
                "Your balance token not enough"
            );
            require(
                IInscription(token.addr).allowance(msg.sender, address(this)) >=
                    mintData[msg.sender].tokenAmount,
                "Your allowance not enough"
            );

            // Burn the tokens from msg.sender
            IInscription(token.addr).burnFrom(
                msg.sender,
                mintData[msg.sender].tokenAmount
            );
        }

        // Burn the token liquidity in this contract
        uint128 refundToken = (mintData[msg.sender].tokenLiquidity *
            token.refundFee) / 10000;
        IInscription(token.addr).burn(
            address(this),
            mintData[msg.sender].tokenLiquidity - refundToken
        );

        // Refund Ether
        uint128 refundEth = (mintData[msg.sender].ethAmount * token.refundFee) /
            10000;
        weth.withdraw(mintData[msg.sender].ethAmount - refundEth); // Change WETH to ETH
        TransferHelper.safeTransferETH(
            msg.sender,
            mintData[msg.sender].ethAmount - refundEth
        ); // Send balance to donator

        totalRefundedAmount =
            totalRefundedAmount +
            mintData[msg.sender].tokenAmount +
            mintData[msg.sender].tokenLiquidity -
            refundToken;

        emit Refund(
            msg.sender,
            mintData[msg.sender].ethAmount - refundEth,
            mintData[msg.sender].tokenAmount,
            mintData[msg.sender].tokenLiquidity - refundToken,
            token.refundFee
        );

        mintData[msg.sender].tokenAmount = 0;
        mintData[msg.sender].tokenLiquidity = 0;
        mintData[msg.sender].ethAmount = 0;
    }

    function positions(
        uint128 pageNo,
        uint128 pageSize
    ) public view returns (Position[] memory _positions) {
        require(pageNo > 0 && pageSize > 0, "pageNo and size can not be zero");
        Position[] memory filtered = new Position[](tokenIdCount);
        uint128 count = 0;
        for (uint128 i = 0; i < tokenIdCount; i++) {
            (
                uint96 nonce,
                address operator,
                address token0,
                address token1,
                uint24 fee,
                int24 tickLower,
                int24 tickUpper,
                uint128 liquidity,
                uint256 feeGrowthInside0LastX128,
                uint256 feeGrowthInside1LastX128,
                uint128 tokensOwed0,
                uint128 tokensOwed1
            ) = nonfungiblePositionManager.positions(tokenIds[i]);
            if (liquidity == 0) continue;
            filtered[count] = Position(
                nonce,
                operator,
                token0,
                token1,
                fee,
                tickLower,
                tickUpper,
                liquidity,
                feeGrowthInside0LastX128,
                feeGrowthInside1LastX128,
                tokensOwed0,
                tokensOwed1,
                tokenIds[i]
            );
            count++;
        }

        uint128 startIndex = (pageNo - 1) * pageSize;
        if (startIndex > count) return new Position[](0);

        _positions = new Position[](pageSize);
        uint128 index;
        for (uint128 i = 0; i < filtered.length; i++) {
            if (i >= startIndex && i < startIndex + pageSize) {
                _positions[index] = filtered[i];
                index++;
            } else continue;
        }
    }

    // Call from Inscription::mint only
    function setMintData(
        address _addr,
        uint128 _ethAmount,
        uint128 _tokenAmount,
        uint128 _tokenLiquidity
    ) public {
        require(msg.sender == token.addr, "Only call from inscription allowed");
        require(
            _ethAmount > 0 &&
                _tokenAmount > 0 &&
                _tokenLiquidity > 0 &&
                _addr > address(0x0),
            "setEtherLiquidity wrong params"
        );

        mintData[_addr].ethAmount = mintData[_addr].ethAmount + _ethAmount;
        mintData[_addr].tokenAmount =
            mintData[_addr].tokenAmount +
            _tokenAmount;
        mintData[_addr].tokenLiquidity =
            mintData[_addr].tokenLiquidity +
            _tokenLiquidity;

        emit MintDeposit(msg.sender, _ethAmount, _tokenAmount, _tokenLiquidity);
    }

    function collectFee(
        uint256 _tokenId
    ) public returns (uint256 amount0, uint256 amount1) {
        // Collect
        INonfungiblePositionManager.CollectParams
            memory params = INonfungiblePositionManager.CollectParams({
                tokenId: _tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });
        (amount0, amount1) = nonfungiblePositionManager.collect(params);
    }

    function _mintNewPosition(
        uint amount0ToAdd,
        uint amount1ToAdd,
        int24 lowerTick,
        int24 upperTick,
        uint16 slippage
    )
        private
        returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1)
    {
        // If weth < ferc20, set token0/amount0 is weth and token1/amount1 is ferc20
        // Otherwise, set token0/amount0 is ferc20, and token1/amount1 is weth
        address _token0;
        address _token1;
        uint _amount0;
        uint _amount1;
        int24 _lowerTick;
        int24 _upperTick;
        if (address(weth) > token.addr) {
            _token0 = token.addr;
            _token1 = address(weth);
            _amount0 = amount1ToAdd;
            _amount1 = amount0ToAdd;
            _lowerTick = lowerTick;
            _upperTick = upperTick;
        } else {
            _token0 = address(weth);
            _token1 = token.addr;
            _amount0 = amount0ToAdd;
            _amount1 = amount1ToAdd;
            _lowerTick = -upperTick;
            _upperTick = -lowerTick;
        }

        // Approve the position manager
        TransferHelper.safeApprove(
            _token0,
            address(nonfungiblePositionManager),
            _amount0
        );
        TransferHelper.safeApprove(
            _token1,
            address(nonfungiblePositionManager),
            _amount1
        );

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
            .MintParams({
                token0: _token0,
                token1: _token1,
                fee: UNISWAP_FEE,
                tickLower: (lowerTick / TICK_SPACING) * TICK_SPACING, // full range
                tickUpper: (upperTick / TICK_SPACING) * TICK_SPACING,
                amount0Desired: _amount0,
                amount1Desired: _amount1,
                amount0Min: (_amount0 * (10000 - slippage)) / 10000, // slipage
                amount1Min: (_amount1 * (10000 - slippage)) / 10000,
                recipient: address(this),
                deadline: block.timestamp
            });

        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);

        _createDeposit(msg.sender, tokenId);

        if (amount0 < _amount0) {
            TransferHelper.safeApprove(
                _token0,
                address(nonfungiblePositionManager),
                0
            );
        }

        if (amount1 < _amount1) {
            TransferHelper.safeApprove(
                _token1,
                address(nonfungiblePositionManager),
                0
            );
        }
    }

    function _createDeposit(address _operator, uint _tokenId) private {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            ,
            ,
            uint128 liquidity,
            ,
            ,
            ,

        ) = nonfungiblePositionManager.positions(_tokenId);

        if (deposits[_tokenId].owner == address(0x0)) {
            tokenIds[tokenIdCount] = _tokenId;
            tokenIdCount++;
        }

        deposits[_tokenId] = Deposit({
            owner: _operator,
            liquidity: liquidity,
            token0: token0,
            token1: token1
        });
    }

    // function onERC721Received(
    //     address operator,
    //     address from,
    //     uint tokenId,
    //     bytes calldata
    // ) public returns (bytes4) {
    //     _createDeposit(operator, tokenId);
    //     return IERC721Receiver.onERC721Received.selector;
    // }

    // Add liquidity with lower/upper tick
    // function addLiquidity(
    //     uint16 ratio,            // The ratio of balance of eths and tokens will be added to liquidity pool
    //     int24 lowerTick,
    //     int24 upperTick,
    //     uint16 slippage
    // ) public {
    //     require(ratio > 0 && ratio <= 10000, "ratio error");
    //     require(slippage >= 0 && slippage <= 10000, "slippage error");
    //     require(IInscription(token.addr).balanceOf(msg.sender) >= token.minBalanceToManagerLiquidity, "Balance not enough to add liquidity");
    //     require(IInscription(token.addr).totalRollups() >= token.maxRollups, "mint not finished");
    //     require(uniswapV3Factory.getPool(address(weth), token.addr, UNISWAP_FEE) > address(0x0), "Pool not exist, create pool in uniswapV3 manually");
    //     require(token.liquidityEtherPercent > 0, "no liquidity add");
    //     uint256 totalTokenLiquidity = IInscription(token.addr).balanceOf(address(this));
    //     require(totalTokenLiquidity > 0, "no token in fto");
    //     uint256 balanceOfWeth = IWETH(weth).balanceOf(address(this));
    //     require(balanceOfWeth > 0, "no eth in fto");

    //     // Send ether back to deployer, the eth liquidity is based on the balance of this contract. So, anyone can send eth to this contract
    //     uint256 backToDeployAmount = balanceOfWeth * (10000 - token.liquidityEtherPercent) * ratio / 100000000;
    //     uint256 maxBackToDeployAmount = token.maxRollups * (10000 - inscriptionFactory.fundingCommission()) * token.crowdFundingRate * (10000 - token.liquidityEtherPercent) / 100000000;

    //     uint256 sum = totalBackToDeployAmount + backToDeployAmount;

    //     if(sum <= maxBackToDeployAmount) {
    //         weth.withdraw(backToDeployAmount);  // Change WETH to ETH
    //         TransferHelper.safeTransferETH(token.deployer, backToDeployAmount);
    //         totalBackToDeployAmount += backToDeployAmount;
    //     } else {
    //         backToDeployAmount = 0;
    //     }

    //     _mintNewPosition(
    //         balanceOfWeth * ratio / 10000 - backToDeployAmount,
    //         totalTokenLiquidity * ratio / 10000,  // ferc20 token amount
    //         lowerTick == 0 ? MIN_TICK : lowerTick,
    //         upperTick == 0 ? MAX_TICK : upperTick,
    //         slippage
    //     );
    // }

    // function decreaseLiquidity(
    //     uint tokenId
    // ) public returns (uint amount0, uint amount1) {
    //     require(IInscription(token.addr).totalRollups() >= token.maxRollups, "mint not finished");
    //     require(IInscription(token.addr).balanceOf(msg.sender) >= token.minBalanceToManagerLiquidity, "Balance not enough to decrease liquidity");
    //     uint128 decreaseLiquidityAmount = deposits[tokenId].liquidity;

    //     INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
    //         tokenId: tokenId,
    //         liquidity: decreaseLiquidityAmount,
    //         amount0Min: 0,
    //         amount1Min: 0,
    //         deadline: block.timestamp
    //     });

    //     (amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

    //     // Collect
    //     INonfungiblePositionManager.CollectParams memory params2 = INonfungiblePositionManager.CollectParams({
    //         tokenId: tokenId,
    //         recipient: address(this),
    //         amount0Max: type(uint128).max,
    //         amount1Max: type(uint128).max
    //     });

    //     (amount0, amount1) = nonfungiblePositionManager.collect(params2);

    //     deposits[tokenId].liquidity = 0;
    // }

    // function setMinBalanceToManagerLiquidity(uint128 _minBalanceToManagerLiquidity) public {
    //     require(msg.sender == token.deployer, "Call must be deployer");
    //     token.minBalanceToManagerLiquidity = _minBalanceToManagerLiquidity;
    // }
}

