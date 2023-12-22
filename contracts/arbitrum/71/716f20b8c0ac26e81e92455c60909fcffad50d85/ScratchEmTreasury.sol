// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./IScratchEmTreasury.sol";
import "./IScratchGames.sol";

import "./ISushiswapRouter.sol";

contract ScratchEmTreasury is Ownable, IScratchEmTreasury, ReentrancyGuard {
    /// TOKEN VARIABLES
    address[] public playableTokens;
    mapping(address => bool) public isPlayableToken;

    mapping(address => uint256) public unclaimedRewards;

    ISushiswapRouter public sushiRouter;

    /// user => token => amount
    mapping(address => mapping(address => uint256))
        public unclaimedRewardsPerUser;

    mapping(address => mapping(address => bool)) internal hasRewardsInGame;
    mapping(address => address[]) internal gamesWithRewards;

    mapping(address => mapping(uint256 => uint)) public nonceLocked;
    mapping(address => mapping(uint256 => address)) public nonceToken;
    mapping(address => mapping(uint256 => address)) public nonceUser;

    /// GAME VARIABLES
    mapping(address => bool) public isGame;

    /// EVENTS

    event PlayableTokenAdded(address token);
    event PlayableTokenRemoved(address token);

    event Deposit(address token, uint256 amount);
    event Withdraw(address token, uint256 amount);

    event GameAdded(address game);
    event GameRemoved(address game);

    event GameDeposit(address from, address token, uint256 amount);
    event GameWithdraw(address token, uint256 amount, address to);

    event NonceLocked(address user, address token, uint256 amount);
    event NonceUnlocked(address user, address token, uint256 amount);

    event GameResulted(address game, address token, uint256 amount);
    event RewardsClaimed(address user, address token, uint256 amount);

    /// MODIFIERS

    /// @notice only games can call
    modifier onlyGame() {
        require(
            isGame[msg.sender],
            "ScratchEmTreasury: only games can call this function"
        );
        _;
    }

    /// @notice only playable tokens can be used
    modifier onlyPlayableToken(address token) {
        require(
            isPlayableToken[token],
            "ScratchEmTreasury: token is not playable"
        );
        _;
    }

    /// CONSTRUCTOR
    constructor(address[] memory _playableTokens, address _sushiRouter) {
        for (uint256 i = 0; i < _playableTokens.length; i++) {
            playableTokens.push(_playableTokens[i]);
            isPlayableToken[_playableTokens[i]] = true;
        }
        sushiRouter = ISushiswapRouter(_sushiRouter);
    }

    /// SETTERS

    /// @notice set the sushi router
    /// @param _sushiRouter address of sushi router
    function setSushiRouter(address _sushiRouter) external onlyOwner {
        sushiRouter = ISushiswapRouter(_sushiRouter);
    }

    /// TOKEN CONTROL

    /// @notice add a token to the list of playable tokens
    /// @param token address of token to add
    function addPlayableToken(address token) external onlyOwner {
        playableTokens.push(token);
        isPlayableToken[token] = true;
        emit PlayableTokenAdded(token);
    }

    /// @notice remove a token from the list of playable tokens
    /// @param token address of token to remove
    function removePlayableToken(
        address token
    ) external onlyOwner onlyPlayableToken(token) {
        for (uint256 i = 0; i < playableTokens.length; i++) {
            if (playableTokens[i] == token) {
                playableTokens[i] = playableTokens[playableTokens.length - 1];
                playableTokens.pop();
                break;
            }
        }
        emit PlayableTokenRemoved(token);
    }

    /// GAME CONTROL

    /// @notice add a game to the list of playable games
    /// @param game address of game to add
    function addGame(address game) external onlyOwner {
        require(!isGame[game], "ScratchEmTreasury: game is already playable");
        isGame[game] = true;
        emit GameAdded(game);
    }

    /// @notice remove a game from the list of playable games
    /// @param game address of game to remove
    function removeGame(address game) external onlyOwner {
        require(isGame[game], "ScratchEmTreasury: game is not playable");
        isGame[game] = false;
        emit GameRemoved(game);
    }

    function gameDeposit(
        address token,
        uint256 amount
    ) external onlyPlayableToken(token) nonReentrant onlyGame {
        if (!hasRewardsInGame[tx.origin][msg.sender]) {
            gamesWithRewards[tx.origin].push(msg.sender);
            hasRewardsInGame[tx.origin][msg.sender] = true;
        }
        bool success = IERC20(token).transferFrom(
            tx.origin,
            address(this),
            amount
        );
        require(success, "ScratchEmTreasury: transfer failed");
        emit GameDeposit(tx.origin, token, amount);
    }

    function gameWithdraw(
        address to,
        address token,
        uint256 amount
    ) external onlyPlayableToken(token) nonReentrant onlyGame {
        require(
            unclaimedRewards[token] >= amount,
            "ScratchEmTreasury: not enough unclaimed rewards"
        );
        bool success = IERC20(token).transfer(to, amount);
        require(success, "ScratchEmTreasury: transfer failed");
        emit GameWithdraw(token, amount, to);
    }

    function gameResult(
        address to,
        address token,
        uint256 amount
    ) external nonReentrant onlyPlayableToken(token) onlyGame {
        if (!hasRewardsInGame[to][msg.sender]) {
            gamesWithRewards[to].push(msg.sender);
            hasRewardsInGame[to][msg.sender] = true;
        }
        unclaimedRewards[token] += amount;
        unclaimedRewardsPerUser[to][token] =
            unclaimedRewardsPerUser[to][token] +
            amount;

        emit GameResulted(to, token, amount);
    }

    function nonceLock(
        uint nonce,
        address user,
        address token,
        uint256 amount
    ) external payable onlyGame {
        if (!hasRewardsInGame[tx.origin][msg.sender]) {
            gamesWithRewards[tx.origin].push(msg.sender);
            hasRewardsInGame[tx.origin][msg.sender] = true;
        }
        if (token == address(0)) {
            nonceLocked[msg.sender][nonce] = amount;
            nonceUser[msg.sender][nonce] = user;
            unclaimedRewards[token] += msg.value;
        } else {
            nonceLocked[msg.sender][nonce] = amount;
            nonceToken[msg.sender][nonce] = token;
            nonceUser[msg.sender][nonce] = user;
            unclaimedRewards[token] += amount;
            IERC20(token).transferFrom(user, address(this), amount);
        }
        emit NonceLocked(user, token, amount);
    }

    /// @notice unlock a nonce
    /// @param nonce nonce to unlock
    /// @param swapType type of swap to perform
    /// (0 = no swap, 1 = swap from token to ETH, 2 = swap from ETH to token, 3 = swap from token to token)
    /// @param path path to swap through
    /// @param burnCut amount to burn
    /// @param afterTransferCut amount to transfer after swap
    /// @param afterTransferToken token to transfer after swap
    /// @param afterTransferAddress address to transfer after swap
    function nonceUnlock(
        uint nonce,
        uint8 swapType,
        address[] calldata path,
        uint burnCut,
        uint afterTransferCut,
        address afterTransferToken,
        address afterTransferAddress
    ) external onlyGame {
        require(
            nonceLocked[msg.sender][nonce] > 0,
            "ScratchEmTreasury: nonce not locked"
        );
        address token = nonceToken[msg.sender][nonce];
        address user = nonceUser[msg.sender][nonce];
        uint256 amount = nonceLocked[msg.sender][nonce];
        nonceLocked[msg.sender][nonce] = 0;
        unclaimedRewards[token] -= amount;
        if (burnCut > 0) {
            _burnToken(amount, token, burnCut);
        }
        if (swapType == 1) {
            _swapTokensForETH(amount, path);
        } else if (swapType == 2) {
            _swapETHForTokens(amount, path);
        } else if (swapType == 3) {
            _swapTokensForTokens(amount, path);
        }
        if (afterTransferCut > 0) {
            uint afterTransferAmount = (amount * afterTransferCut) / 100;
            IERC20(afterTransferToken).transfer(
                afterTransferAddress,
                afterTransferAmount
            );
        }
        emit NonceUnlocked(user, token, 0);
    }

    function _burnToken(
        uint amount,
        address token,
        uint256 burnCut
    ) internal returns (uint256) {
        amount = (amount * burnCut) / 100;
        IERC20(token).transfer(
            0x000000000000000000000000000000000000dEaD,
            amount
        );
        return amount;
    }

    function _swapETHForTokens(uint amount, address[] calldata path) internal {
        sushiRouter.swapExactETHForTokens{value: amount}(
            0,
            path,
            address(this),
            block.timestamp + 60
        );
    }

    function _swapTokensForETH(uint amount, address[] calldata path) internal {
        IERC20(path[0]).approve(address(sushiRouter), amount);
        sushiRouter.swapExactTokensForETH(
            amount,
            0,
            path,
            address(this),
            block.timestamp + 60
        );
    }

    function _swapTokensForTokens(
        uint amount,
        address[] calldata path
    ) internal {
        IERC20(path[0]).approve(address(sushiRouter), amount);
        sushiRouter.swapExactTokensForTokens(
            amount,
            0,
            path,
            address(this),
            block.timestamp + 60
        );
    }

    function nonceRevert(uint nonce) external onlyGame {
        require(
            nonceLocked[msg.sender][nonce] > 0,
            "ScratchEmTreasury: nonce not locked"
        );
        address token = nonceToken[msg.sender][nonce];
        address user = nonceUser[msg.sender][nonce];
        uint256 amount = nonceLocked[msg.sender][nonce];
        nonceLocked[msg.sender][nonce] = 0;
        unclaimedRewards[token] -= amount;
        IERC20(token).transfer(user, amount);
        emit NonceUnlocked(user, token, amount);
    }

    function claimableRewards(
        address user
    ) public view returns (uint256[] memory total) {
        total = new uint256[](playableTokens.length);
        for (uint256 i = 0; i < playableTokens.length; i++) {
            total[i] = unclaimedRewardsPerUser[user][playableTokens[i]];
        }
    }

    function claimRewards() external nonReentrant {
        address[] memory _games = gamesWithRewards[msg.sender];
        for (uint256 i = 0; i < _games.length; i++) {
            IScratchGames(_games[i]).scratchAndClaimAllCardsTreasury();
        }
        for (uint256 i = 0; i < playableTokens.length; i++) {
            address token = playableTokens[i];
            uint256 amount = unclaimedRewardsPerUser[msg.sender][token];
            if (amount > 0) {
                unclaimedRewardsPerUser[msg.sender][token] = 0;
                unclaimedRewards[token] -= amount;
                bool success = IERC20(token).transfer(msg.sender, amount);
                require(success, "ScratchEmTreasury: transfer failed");
                emit RewardsClaimed(msg.sender, token, amount);
            }
        }
    }

    function claimRewardsByGame(
        address user,
        address token,
        uint amount
    ) external nonReentrant onlyPlayableToken(token) onlyGame {
        require(
            unclaimedRewardsPerUser[user][token] >= amount,
            "ScratchEmTreasury: not enough unclaimed rewards"
        );
        unclaimedRewards[token] -= amount;
        unclaimedRewardsPerUser[user][token] -= amount;
        bool success = IERC20(token).transfer(user, amount);
        require(success, "ScratchEmTreasury: transfer failed");
        emit RewardsClaimed(user, token, amount);
    }

    function scratchAllCardsTreasury() external {
        address[] memory _games = gamesWithRewards[msg.sender];
        for (uint256 i = 0; i < _games.length; i++) {
            IScratchGames(_games[i]).scratchAllCardsTreasury();
        }
    }

    function burnAllCardsTreasury() external {
        address[] memory _games = gamesWithRewards[msg.sender];
        for (uint256 i = 0; i < _games.length; i++) {
            IScratchGames(_games[i]).burnAllCardsTreasury();
        }
    }

    /// DEPOSIT AND WITHDRAW

    function deposit(
        address token,
        uint256 amount
    ) external onlyPlayableToken(token) {
        bool success = IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "ScratchEmTreasury: transfer failed");
        emit Deposit(token, amount);
    }

    function withdraw(
        address token,
        uint256 amount
    ) external onlyOwner onlyPlayableToken(token) {
        require(amount > 0, "ScratchEmTreasury: amount must be greater than 0");
        uint balance = IERC20(token).balanceOf(address(this));
        require(
            balance - unclaimedRewards[token] >= amount,
            "ScratchEmTreasury: not enough balance"
        );
        bool success = IERC20(token).transfer(msg.sender, amount);
        require(success, "ScratchEmTreasury: transfer failed");
        emit Withdraw(token, amount);
    }

    function withdrawAll(
        address token
    ) external onlyOwner onlyPlayableToken(token) {
        uint256 balance = IERC20(token).balanceOf(address(this));
        require(
            balance - unclaimedRewards[token] > 0,
            "ScratchEmTreasury: not enough balance"
        );
        bool success = IERC20(token).transfer(
            msg.sender,
            balance - unclaimedRewards[token]
        );
        require(success, "ScratchEmTreasury: transfer failed");
        emit Withdraw(token, balance - unclaimedRewards[token]);
    }
}

