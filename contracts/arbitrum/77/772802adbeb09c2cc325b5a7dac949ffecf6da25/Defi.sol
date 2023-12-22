// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IUniswapV3Pool.sol";
import "./INonfungiblePositionManager.sol";
import "./IERC20Metadata.sol";
import "./IIGamesNFT.sol";
import "./IWETH9.sol";

contract Defi is Ownable {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;

    struct Account {
        uint256 id;
        address referrer;
        uint256 createdTime;
        address[] recommends;
        mapping(address => uint256) dividends;
        mapping(address => uint256) dividendsWithdraw;
        mapping(address => uint256) awards;
    }

    struct Pool {
        address token0;
        address token1;
        uint24 fee;
    }

    struct TokenInfo {
        string symbol;
        uint8 decimals;
    }

    struct AccountLiquidity {
        address account;
        uint160 liquidity;
    }

    struct TokenAmountRes {
        address token;
        string symbol;
        uint8 decimals;
        uint256 dividends;
        uint256 dividendsWithdraw;
        uint256 awards;
    }

    struct ShareholderRes {
        address account;
        uint256 createdTime;
        uint160 liquidity;
    }

    event Bind(address indexed account, address referrer);
    event Withdraw(address indexed account, address token, uint256 amount);
    event Mint(address indexed account);

    address public constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    address public constant WETH9 = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    address public constant MARKETING = 0xb728c15C35ADF40A8627a6dfA2614D8E84f03361;

    address public _igs;

    address public _uniswapV3Pool;
    Pool public _pool;
    address public _nftToken;

    uint256 public _maxShareholderCount = 100;

    uint16 public _shareFee = 2000;

    mapping(address => Account) public _accountMap;
    address[] public _accounts;
    uint256 private _lastId = 1;

    EnumerableSet.AddressSet private _dividends;
    mapping(address => TokenInfo) private _tokenInfoMap;

    function setIGS(address token) external onlyOwner {
        _igs = token;
    }

    function setUniswapV3Pool(address uniswapV3Pool) external onlyOwner {
        _uniswapV3Pool = uniswapV3Pool;
        _pool.token0 = IUniswapV3Pool(_uniswapV3Pool).token0();
        _pool.token1 = IUniswapV3Pool(_uniswapV3Pool).token1();
        _pool.fee = IUniswapV3Pool(_uniswapV3Pool).fee();
    }

    function setNFTToken(address nftToken) external onlyOwner {
        _nftToken = nftToken;
    }

    function setMaxShareholderCount(uint256 count) external onlyOwner {
        _maxShareholderCount = count;
    }

    function setShareFee(uint16 fee) external onlyOwner {
        _shareFee = fee;
    }

    function bind(address referrer) external {
        address sender = _msgSender();
        if (_accountMap[sender].id != 0) return;

        require(referrer == MARKETING || (_accountMap[referrer].id != 0), "Registered: referrer is not registered or not shareholder");
        Account storage accountInfo = _accountMap[sender];
        accountInfo.id = _lastId;
        accountInfo.referrer = referrer;
        accountInfo.createdTime = block.timestamp;
        _lastId ++;
        _accountMap[referrer].recommends.push(msg.sender);
        _accounts.push(sender);
        
        emit Bind(sender, referrer);
    }

    function mint() external {
        require(_nftToken != address(0), "Defi: NFT not init");
        address sender = _msgSender();
        require(IIGamesNFT(_nftToken).balanceOf(sender) == 0, "Defi: can not mint");
        require(isShareholder(sender), "Defi: not shareholder");
        IIGamesNFT(_nftToken).mint(sender);

        emit Mint(sender);
    }

    function withdraw(address token, uint256 amount) external {
        address sender = _msgSender();
        require(_accountMap[sender].id != 0, "Registered: not registered");
        Account storage accountInfo = _accountMap[sender];
        uint256 balance = accountInfo.dividends[token];
        require(balance >= amount, "Defi: amount exceeds balance");

        if (token == WETH9) {
            IWETH9(WETH9).withdraw(amount);
        }

        if (accountInfo.referrer == MARKETING) {
            if (token == WETH9) {
                payable(sender).transfer(amount);
            } else {
                IERC20(token).safeTransfer(sender, amount);
            }
        } else {
            uint256 fee = amount.mul(_shareFee).div(10000);

            if (token == WETH9) {
                payable(accountInfo.referrer).transfer(fee);
                payable(sender).transfer(amount.sub(fee));
            } else {
                IERC20(token).safeTransfer(accountInfo.referrer, fee);
                IERC20(token).safeTransfer(sender, amount.sub(fee));
            }
            _accountMap[accountInfo.referrer].awards[token] += fee;
        }

        accountInfo.dividends[token] -= amount;
        accountInfo.dividendsWithdraw[token] += amount;

        emit Withdraw(sender, token, amount);
    }

    function isBind(address account) public view returns(bool) {
        return _accountMap[account].id != 0;
    }

    function isShareholder(address account) public view returns(bool) {
        if (_accountMap[account].id == 0) return false;
        if (_poolLiquidityForAccount(account) == 0) return false;
        if (_accounts.length <= _maxShareholderCount) return true;
        AccountLiquidity[] memory accountLiquidities = _shareholderLiquidities();
        for (uint256 i = 0; i < accountLiquidities.length; i ++) {
            if (accountLiquidities[i].account == account) return true;
        }
        return false;
    }

    function getLiquidityGross(address account) public view returns(uint160) {
        return _poolLiquidityForAccount(account);
    }

    function shareholderCount() public view returns(uint256) {
        return _shareholderLiquidities().length;
    }

    function shareholders() public view returns (ShareholderRes[] memory) {
        AccountLiquidity[] memory accountLiquidities = _shareholderLiquidities();
        ShareholderRes[] memory result = new ShareholderRes[](accountLiquidities.length);
        for (uint256 i = 0; i < accountLiquidities.length; i ++) {
            result[i].account = accountLiquidities[i].account;
            result[i].liquidity = accountLiquidities[i].liquidity;
            result[i].createdTime = _accountMap[accountLiquidities[i].account].createdTime;
        }
        return result;
    }

    function poolSqrtPriceX96() external view returns(uint160) {
        if (_uniswapV3Pool == address(0)) return 0;
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool).slot0();
        return sqrtPriceX96;
    }

    function dividendsRecord(address account) external view returns(TokenAmountRes[] memory) {
        if (_accountMap[account].id == 0) return new TokenAmountRes[](0);

        uint256 currentIndex = 0;

        for (uint i = 0; i < _dividends.length(); i++) {
            address token = _dividends.at(i);
            if (
                _accountMap[account].dividends[token] > 0 ||
                _accountMap[account].dividendsWithdraw[token] > 0 ||
                _accountMap[account].awards[token] > 0
                ) 
            {
                currentIndex ++;
            }
        }

        TokenAmountRes[] memory results = new TokenAmountRes[](currentIndex);
        currentIndex = 0;
        for (uint i = 0; i < _dividends.length(); i++) {
            address token = _dividends.at(i);
            uint256 dividends = _accountMap[account].dividends[token];
            uint256 dividendWithdraw = _accountMap[account].dividendsWithdraw[token];
            uint256 awards = _accountMap[account].awards[token];
            if (dividends > 0 || dividendWithdraw > 0 || awards > 0) {
                results[currentIndex] = TokenAmountRes(
                    token, 
                    _tokenInfoMap[token].symbol, 
                    _tokenInfoMap[token].decimals,
                    dividends,
                    dividendWithdraw,
                    awards
                );
                currentIndex ++;
            }
        }
        return results;
    }

    function recommends(address account) external view returns(AccountLiquidity[] memory) {
        if (_accountMap[account].id == 0) return new AccountLiquidity[](0);

        Account storage accountInfo = _accountMap[account];

        AccountLiquidity[] memory results = new AccountLiquidity[](accountInfo.recommends.length);

        for (uint256 i = 0; i < accountInfo.recommends.length; i ++) {
            address recommend = accountInfo.recommends[i];
            results[i] = AccountLiquidity(
                recommend,
                _poolLiquidityForAccount(recommend)
            );
        }
        return results;
    }

    function recommendCount(address account) external view returns(uint256) {
        if (_accountMap[account].id == 0) return 0;
        return _accountMap[account].recommends.length;
    }

    function recommendLiquidityGross(address account) external view returns(uint128) {
        if (_accountMap[account].id == 0) return 0;
        uint128 liquidityGross = 0;
        for (uint256 i = 0; i < _accountMap[account].recommends.length; i++) {
            liquidityGross += _poolLiquidityForAccount(_accountMap[account].recommends[i]);
        }
        return liquidityGross;
    }

    function gameDividend(address token, uint256 amount) external onlyOwner {
        require(_uniswapV3Pool != address(0), "Defi: pool not init");
        require(amount > 0, "Defi: amount not be zero");
        IERC20(token).safeTransferFrom(_msgSender(), address(this), amount);
        if (!_dividends.contains(token)) {
            _dividends.add(token);
            if (token == WETH9) {
                _tokenInfoMap[token].symbol = "ETH";    
            } else {
                _tokenInfoMap[token].symbol = IERC20Metadata(token).symbol();
            }
            _tokenInfoMap[token].decimals = IERC20Metadata(token).decimals();
        }
        uint128 liquidityGross = IUniswapV3Pool(_uniswapV3Pool).liquidity();

        AccountLiquidity[] memory shareholderLiquidities = _shareholderLiquidities();
        for (uint256 i = 0; i < shareholderLiquidities.length; i ++) {
            address account = shareholderLiquidities[i].account;
            uint256 liquidity = shareholderLiquidities[i].liquidity;
            if (liquidity == 0) continue;
            _accountMap[account].dividends[token] = _accountMap[account].dividends[token].add(amount.mul(liquidity).div(uint256(liquidityGross)));
        }
    }

    function gameWithdraw(address token, uint256 amount, address recipient) external onlyOwner {
        IERC20(token).safeTransfer(recipient, amount);
    }

    function _poolLiquidityForAccount(address account) private view returns(uint128 liquidityGross) {
        if (_uniswapV3Pool == address(0) || _accountMap[account].id == 0) return 0;
        uint256 balance = INonfungiblePositionManager(POSITION_MANAGER).balanceOf(account);
        if (balance == 0) return 0;

        for (uint256 i = 0; i < balance; i++) {
            uint256 tokenId = INonfungiblePositionManager(POSITION_MANAGER).tokenOfOwnerByIndex(account, i);
            (
                , 
                , 
                address token0, 
                address token1, 
                uint24 fee, 
                , 
                , 
                uint128 liquidity,
                ,
                ,
                ,
            ) = INonfungiblePositionManager(POSITION_MANAGER).positions(tokenId);
            if (_pool.token0 == token0 && _pool.token1 == token1 && _pool.fee == fee && liquidity > 0) {
                liquidityGross += liquidity;
            }
        }
    }

    function _shareholderLiquidities() private view returns (AccountLiquidity[] memory) {
        AccountLiquidity[] memory accountLiquidities = new AccountLiquidity[](_accounts.length);

        uint256 count = 0;

        for (uint256 i = 0; i < _accounts.length; i++) {
            uint160 liquidity = _poolLiquidityForAccount(_accounts[i]);
            if (liquidity > 0) {
                accountLiquidities[count].account = _accounts[i];
                accountLiquidities[count].liquidity = liquidity;
                count ++;
            }
        }

        for (uint256 i = 1; i < count; i++) {
            AccountLiquidity memory temp = accountLiquidities[i];
            uint256 j = i;
            while ((j >= 1) && (temp.liquidity > accountLiquidities[j - 1].liquidity)) {
                accountLiquidities[j] = accountLiquidities[j - 1];
                j--;
            }
            accountLiquidities[j] = temp;
        }

        AccountLiquidity[] memory newAccountLiquidities = new AccountLiquidity[](_maxShareholderCount);
        for (uint256 i = 0; i < _maxShareholderCount && i < count; i ++) {
            newAccountLiquidities[i] = accountLiquidities[i];
        }

        return newAccountLiquidities;
    }
}
