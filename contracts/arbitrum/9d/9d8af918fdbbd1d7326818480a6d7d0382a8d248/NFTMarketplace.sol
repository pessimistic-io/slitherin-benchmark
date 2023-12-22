// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import { Initializable } from "./Initializable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { ERC721AQueryableUpgradeable } from "./ERC721AQueryableUpgradeable.sol";

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "./SafeERC20Upgradeable.sol";
import { ERC721AUpgradeable } from "./ERC721AUpgradeable.sol";
import { IERC721AUpgradeable } from "./interfaces_IERC721AUpgradeable.sol";

import { IWETH } from "./IWETH.sol";
import { IBaseReward } from "./IBaseReward.sol";
import { Multicall } from "./Multicall.sol";

contract NFTMarketplace is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC721AQueryableUpgradeable, Multicall {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 private constant PRECISION = 1e18;

    address public wethAddress;

    struct PoolInfo {
        address vsToken;
        uint256 totalLiquidity;
        uint256 accRewardPerShare;
        uint256 queuedRewards;
        address rewardPool;
        address rewardToken;
    }

    struct RewardInfo {
        uint256 liquidity;
        uint256 rewards;
        uint256 rewardPerSharePaid;
    }

    struct TokenMeta {
        address underlyingToken;
        address owner;
        uint256 liquidity;
    }

    struct Listing {
        uint256 price;
        uint256 createdAt;
    }

    mapping(address => PoolInfo) public pools;
    mapping(uint256 => RewardInfo) public tokenRewards;
    mapping(uint256 => TokenMeta) public tokenMetas;
    mapping(uint256 => Listing) public listings;

    event Deposit(address indexed _underlyingToken, uint256 _amountIn, bool _listing, uint256 _price);
    event Withdraw(uint256 indexed _tokenId, uint256 _liquidity);
    event Harvest(uint256 _claimed, uint256 _accRewardPerShare, uint256 _totalLiquidity);
    event CancelListing(uint256 indexed _tokenId, address _sender);
    event UpdateListing(uint256 indexed _tokenId, address _sender, uint256 _price);
    event BugItem(uint256 indexed _tokenId, address _owner, address _sender, uint256 _amountIn);
    event AddPool(address indexed _underlyingToken, address _vsToken, address _rewardPool, address _rewardToken);
    event Claim(uint256 indexed _tokenId, address _owner, uint256 _claimed);

    modifier isTokenOwner(uint256 _tokenId, address _sender) {
        require(tokenMetas[_tokenId].owner == _sender, "NFTMarketplace: You are not the holder of the token");
        _;
    }

    modifier notListed(uint256 _tokenId) {
        require(listings[_tokenId].price == 0, "NFTMarketplace: Token has been listed");
        _;
    }

    modifier isListed(uint256 _tokenId) {
        require(listings[_tokenId].price > 0, "NFTMarketplace: Token has not been listed yet");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _wethAddress) external initializerERC721A initializer {
        __ERC721A_init("ArchiFinance OTC Marketplace", "AOM");
        __Ownable_init();
        __ReentrancyGuard_init();

        wethAddress = _wethAddress;
    }

    function deposit(address _underlyingToken, uint256 _amountIn, bool _listing, uint256 _price) public nonReentrant {
        require(_underlyingToken != address(0), "NFTMarketplace: _underlyingToken cannot be 0x0");
        require(_amountIn > 0, "NFTMarketplace: _amountIn cannot be 0");

        if (_listing) {
            require(_price > 0, "NFTMarketplace: _price cannot be 0");
        }

        PoolInfo storage pool = pools[_underlyingToken];

        uint256 before = IERC20Upgradeable(pool.vsToken).balanceOf(address(this));
        IERC20Upgradeable(pool.vsToken).safeTransferFrom(msg.sender, address(this), _amountIn);
        _amountIn = IERC20Upgradeable(pool.vsToken).balanceOf(address(this)) - before;

        uint256 currentTokenId = _nextTokenId();

        _mint(address(this), 1);
        _harvest(_underlyingToken);

        pool.totalLiquidity += _amountIn;
        tokenMetas[currentTokenId] = TokenMeta({ underlyingToken: _underlyingToken, liquidity: _amountIn, owner: msg.sender });

        _approve(pool.vsToken, pool.rewardPool, _amountIn);

        IBaseReward(pool.rewardPool).stakeFor(address(this), _amountIn);

        if (_listing) {
            _listItem(currentTokenId, _price);
        } else {
            IERC721AUpgradeable(address(this)).transferFrom(address(this), msg.sender, currentTokenId);
        }

        emit Deposit(_underlyingToken, _amountIn, _listing, _price);
    }

    function _withdraw(uint256 _tokenId, bool _stake) internal {
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];

        _updateRewards(_tokenId);
        _claim(_tokenId);
        _burn(_tokenId);

        PoolInfo storage pool = pools[tokenMeta.underlyingToken];

        pool.totalLiquidity -= tokenMeta.liquidity;

        IBaseReward(pool.rewardPool).withdraw(tokenMeta.liquidity);

        if (_stake) {
            _approve(pool.vsToken, pool.rewardPool, tokenMeta.liquidity);

            IBaseReward(pool.rewardPool).stakeFor(tokenMeta.owner, tokenMeta.liquidity);
        } else {
            IERC20Upgradeable(pool.vsToken).safeTransfer(tokenMeta.owner, tokenMeta.liquidity);
        }

        delete tokenMetas[_tokenId];
        delete tokenRewards[_tokenId];
        delete listings[_tokenId];

        emit Withdraw(_tokenId, tokenMeta.liquidity);
    }

    function withdraw(uint256 _tokenId, bool _stake) public nonReentrant isTokenOwner(_tokenId, msg.sender) {
        _withdraw(_tokenId, _stake);
    }

    function harvest(address[] calldata _underlyingTokens) public onlyOwner {
        for (uint256 i = 0; i < _underlyingTokens.length; i++) {
            _harvest(_underlyingTokens[i]);
        }
    }

    function _harvest(address _underlyingToken) internal returns (uint256) {
        PoolInfo storage pool = pools[_underlyingToken];
        uint256 claimed = IBaseReward(pool.rewardPool).claim(address(this));

        if (claimed > 0) {
            if (pool.totalLiquidity == 0) {
                pool.queuedRewards = pool.queuedRewards + claimed;
            } else {
                claimed = claimed + pool.queuedRewards;
                pool.accRewardPerShare = pool.accRewardPerShare + (claimed * PRECISION) / pool.totalLiquidity;
                pool.queuedRewards = 0;

                emit Harvest(claimed, pool.accRewardPerShare, pool.totalLiquidity);
            }
        }

        return claimed;
    }

    function _listItem(uint256 _tokenId, uint256 _price) internal {
        listings[_tokenId] = Listing({ price: _price, createdAt: block.timestamp });
    }

    function cancelListing(uint256 _tokenId) external nonReentrant isTokenOwner(_tokenId, msg.sender) isListed(_tokenId) {
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];

        _updateRewards(_tokenId);

        IERC721AUpgradeable(address(this)).transferFrom(address(this), tokenMeta.owner, _tokenId);
        delete listings[_tokenId];

        emit CancelListing(_tokenId, msg.sender);
    }

    function updateListing(uint256 _tokenId, uint256 _price) external nonReentrant isTokenOwner(_tokenId, msg.sender) isListed(_tokenId) {
        require(_price > 0, "NFTMarketplace: _price cannot be 0");

        _updateRewards(_tokenId);

        listings[_tokenId].price = _price;

        emit UpdateListing(_tokenId, msg.sender, _price);
    }

    function listItem(uint256 _tokenId, uint256 _price) external nonReentrant isTokenOwner(_tokenId, msg.sender) notListed(_tokenId) {
        require(_price > 0, "NFTMarketplace: _price cannot be 0");

        _updateRewards(_tokenId);

        IERC721AUpgradeable(address(this)).transferFrom(msg.sender, address(this), _tokenId);

        _listItem(_tokenId, _price);
    }

    function _buyItem(uint256 _tokenId, uint256 _amountIn) internal {
        Listing storage listing = listings[_tokenId];
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];

        _updateRewards(_tokenId);
        _claim(_tokenId);

        if (msg.value > 0 && tokenMeta.underlyingToken == wethAddress) {
            _wrapETH(_amountIn);
        } else {
            uint256 before = IERC20Upgradeable(tokenMeta.underlyingToken).balanceOf(address(this));
            IERC20Upgradeable(tokenMeta.underlyingToken).safeTransferFrom(msg.sender, address(this), _amountIn);
            _amountIn = IERC20Upgradeable(tokenMeta.underlyingToken).balanceOf(address(this)) - before;
        }

        if (_amountIn < listing.price) {
            revert("NFTMarketplace: _amountIn is insufficient");
        }

        IERC721AUpgradeable(address(this)).transferFrom(address(this), msg.sender, _tokenId);
        IERC20Upgradeable(tokenMeta.underlyingToken).safeTransfer(tokenMeta.owner, listing.price);

        tokenMeta.owner = msg.sender;

        if (_amountIn > listing.price) {
            IERC20Upgradeable(tokenMeta.underlyingToken).safeTransfer(msg.sender, _amountIn - listing.price);
        }

        delete listings[_tokenId];

        emit BugItem(_tokenId, tokenMeta.owner, msg.sender, _amountIn);
    }

    function buyItem(uint256 _tokenId, uint256 _amountIn) external payable nonReentrant isListed(_tokenId) {
        require(_amountIn > 0, "NFTMarketplace: _amountIn cannot be 0");

        _buyItem(_tokenId, _amountIn);
    }

    function addPool(address _underlyingToken, address _vsToken, address _rewardPool, address _rewardToken) public onlyOwner {
        require(_underlyingToken != address(0), "NFTMarketplace: _underlyingToken cannot be 0x0");
        require(_vsToken != address(0), "NFTMarketplace: _vsToken cannot be 0x0");
        require(_rewardPool != address(0), "NFTMarketplace: _rewardPool cannot be 0x0");
        require(_rewardToken != address(0), "NFTMarketplace: _rewardToken cannot be 0x0");

        pools[_underlyingToken] = PoolInfo({
            vsToken: _vsToken,
            totalLiquidity: 0,
            accRewardPerShare: 0,
            queuedRewards: 0,
            rewardPool: _rewardPool,
            rewardToken: _rewardToken
        });

        emit AddPool(_underlyingToken, _vsToken, _rewardPool, _rewardToken);
    }

    function _updateRewards(uint256 _tokenId) internal {
        RewardInfo storage tokenReward = tokenRewards[_tokenId];
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];
        PoolInfo storage pool = pools[tokenMeta.underlyingToken];

        _harvest(tokenMeta.underlyingToken);

        uint256 rewards = _checkpoint(tokenReward, pool.accRewardPerShare, tokenMeta.liquidity);

        tokenReward.rewards = rewards;
        tokenReward.rewardPerSharePaid = pool.accRewardPerShare;
    }

    function _claim(uint256 _tokenId) internal returns (uint256 claimed) {
        _updateRewards(_tokenId);

        RewardInfo storage tokenReward = tokenRewards[_tokenId];
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];
        PoolInfo storage pool = pools[tokenMeta.underlyingToken];

        claimed = tokenReward.rewards;

        if (claimed > 0) {
            tokenReward.rewards = 0;
            IERC20Upgradeable(pool.rewardToken).safeTransfer(tokenMeta.owner, claimed);

            emit Claim(_tokenId, tokenMeta.owner, claimed);
        }
    }

    function claim(uint256 _tokenId) external nonReentrant returns (uint256) {
        require(_tokenId > 0, "NFTMarketplace: _tokenId cannot be 0");
        return _claim(_tokenId);
    }

    function _checkpoint(RewardInfo storage _tokenReward, uint256 accRewardPerShare, uint256 _liquidity) internal view returns (uint256) {
        return _tokenReward.rewards + ((accRewardPerShare - _tokenReward.rewardPerSharePaid) * _liquidity) / PRECISION;
    }

    function pendingRewards(uint256 _tokenId) public view returns (uint256) {
        require(_tokenId > 0, "NFTMarketplace: _tokenId cannot be 0");

        RewardInfo storage tokenReward = tokenRewards[_tokenId];
        TokenMeta storage tokenMeta = tokenMetas[_tokenId];
        PoolInfo storage pool = pools[tokenMeta.underlyingToken];

        return _checkpoint(tokenReward, pool.accRewardPerShare, tokenMeta.liquidity);
    }

    function supportsInterface(bytes4 _interfaceId) public view virtual override(ERC721AUpgradeable) returns (bool) {
        return super.supportsInterface(_interfaceId);
    }

    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    function totalMinted() public view returns (uint256) {
        return _totalMinted();
    }

    function _approve(address _token, address _spender, uint256 _amount) internal {
        IERC20Upgradeable(_token).safeApprove(_spender, 0);
        IERC20Upgradeable(_token).safeApprove(_spender, _amount);
    }

    function _wrapETH(uint256 _amountIn) internal {
        require(msg.value == _amountIn, "NFTMarketplace: ETH amount mismatch");

        IWETH(wethAddress).deposit{ value: _amountIn }();
    }
}

