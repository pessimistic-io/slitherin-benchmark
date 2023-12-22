// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.16;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./IArkenOptionRewarder.sol";
import "./IArkenOptionNFT.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IArkenPairLongTermFactory.sol";
import "./IERC721URIProvider.sol";
import "./IArkenPairLongTerm.sol";

contract LiquidityAdder is Ownable {
    using SafeERC20 for IERC20;

    address public factory;
    address public factoryLongTerm;

    constructor(address factory_, address factoryLongTerm_) {
        factory = factory_;
        factoryLongTerm = factoryLongTerm_;
    }

    function updateFactory(address factory_) external onlyOwner {
        factory = factory_;
    }

    function updateFactoryLongTerm(
        address factoryLongTerm_
    ) external onlyOwner {
        factoryLongTerm = factoryLongTerm_;
    }

    function addShortTerm(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) external onlyOwner returns (address pair, uint256 liquidity) {
        require(
            IUniswapV2Factory(factory).getPair(tokenA, tokenB) == address(0),
            'LiquidityAdder: PAIR_EXISTS'
        );
        pair = IUniswapV2Factory(factory).createPair(tokenA, tokenB);
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        liquidity = IUniswapV2Pair(pair).mint(msg.sender);
    }

    function addLongTerm(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 lockTime
    )
        external
        onlyOwner
        returns (address pair, uint256 liquidity, uint256 positionTokenId)
    {
        require(
            IArkenPairLongTermFactory(factoryLongTerm).getPair(
                tokenA,
                tokenB
            ) == address(0),
            'LiquidityAdder: PAIR_EXISTS'
        );
        pair = IArkenPairLongTermFactory(factoryLongTerm).createPair(
            tokenA,
            tokenB
        );
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        IArkenPairLongTerm(pair).unpause(); // unpause for initial liquidity
        (liquidity, positionTokenId) = IArkenPairLongTerm(pair).mint(
            msg.sender,
            lockTime
        );
        IArkenPairLongTerm(pair).pause();
        IArkenPairLongTerm(pair).setPauser(msg.sender);
    }

    function addLongTermWithoutCreate(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 lockTime
    )
        external
        onlyOwner
        returns (address pair, uint256 liquidity, uint256 positionTokenId)
    {
        pair = IArkenPairLongTermFactory(factoryLongTerm).getPair(
            tokenA,
            tokenB
        );
        IERC20(tokenA).safeTransferFrom(msg.sender, pair, amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, pair, amountB);
        IArkenPairLongTerm(pair).unpause(); // unpause for initial liquidity
        (liquidity, positionTokenId) = IArkenPairLongTerm(pair).mint(
            msg.sender,
            lockTime
        );
        IArkenPairLongTerm(pair).pause();
        IArkenPairLongTerm(pair).setPauser(msg.sender);
    }

    function mintReward(
        address rewarder,
        address ltlp,
        uint256 positionTokenId,
        bytes calldata rewardData
    ) external onlyOwner {
        IArkenOptionNFT(ltlp).transferFrom(
            msg.sender,
            rewarder,
            positionTokenId
        );
        IArkenOptionRewarder(rewarder).rewardLongTerm(
            msg.sender,
            ltlp,
            positionTokenId,
            rewardData
        );
    }
}

