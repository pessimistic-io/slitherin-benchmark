// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

interface IWhitelist {
    function isWhitelisted(address) external view returns (bool);
    function canWhitelist(address) external view returns (bool);
}

contract TokenSale is Ownable {

    using SafeERC20 for IERC20;

    uint256 public constant WHITELIST_PRICE = 850_000; // $0.85
    uint256 public constant PUBLIC_FLOOR_PRICE = 900_000; // $0.90
    uint256 public constant WHITELIST_SALE = 300_000 ether;
    uint256 public constant PUBLIC_SALE = 400_000 ether;
    uint256 public constant PUBLIC_RAISE_GOAL = 760000e6; // $760k

    IWhitelist public immutable whitelist;
    IERC20 public immutable tigrisToken;
    IERC20 public immutable token;
    uint256 public immutable startTime;
    uint256 public immutable endTime;
    address public immutable treasury;
    
    uint256 public whitelistSold;
    uint256 public publicRaised;

    mapping(address => uint256) public publicBuyerRaised;

    /**
     * @param _tigrisToken 18 decimals
     * @param _token token used to purchase tigris
     * @param _startTime token sale start
     * @param _treasury address to receive sale funds
     */
    constructor(IERC20 _tigrisToken, IERC20 _token, uint256 _startTime, address _treasury, IWhitelist _whitelist) {
        require(address(_tigrisToken) != address(0)
            && address(_token) != address(0)
            && _treasury != address(0)
            && address(_whitelist) != address(0),
            "Constructor"
        );
        tigrisToken = _tigrisToken;
        token = _token;
        startTime = _startTime;
        endTime = _startTime + 1 days;
        treasury = _treasury;
        whitelist = _whitelist;
    }

    /**
     * @notice Function to buy tigris tokens
     * @param _spendAmount amount of tokens to spend to buy tigris
     * @param _buyPublicIfWhitelistSoldOut true if whitelisted user wants to buy from public sale in case they're late to whitelist sale
     */
    function buy(uint256 _spendAmount, bool _buyPublicIfWhitelistSoldOut) external {

        require(block.timestamp >= startTime, "Sale not started");
        require(block.timestamp < endTime, "Sale ended");
        require(token.balanceOf(msg.sender) >= _spendAmount, "Insufficient balance");

        // Transfer here in case some need to be refunded
        token.safeTransferFrom(msg.sender, address(this), _spendAmount);

        if (whitelist.isWhitelisted(msg.sender) || whitelist.canWhitelist(msg.sender)) {
            _handleWhitelistBuy(_spendAmount, _buyPublicIfWhitelistSoldOut);
        } else {
            _handlePublicBuy(_spendAmount);
        }

        // Send everything to treasury
        token.safeTransfer(treasury, token.balanceOf(address(this)));
    }

    function claimPublic() external {
        require(block.timestamp > endTime, "Sale not ended");
        uint256 _allocation = publicSaleAllocation(msg.sender);
        delete publicBuyerRaised[msg.sender];
        tigrisToken.safeTransfer(msg.sender, _allocation);
    }

    function recover(IERC20 _token, uint256 _amount) external onlyOwner {
        _token.safeTransfer(treasury, _amount);
    }

    function _handleWhitelistBuy(uint256 _spendAmount, bool _buyPublicIfWhitelistSoldOut) internal {
        uint256 _tigrisTokenAmount = _spendAmount * 1e18 / WHITELIST_PRICE;

        // If whitelist is or would be sold out
        if (whitelistSold + _tigrisTokenAmount > WHITELIST_SALE) {
            uint256 _missingWhitelistTokens = whitelistSold + _tigrisTokenAmount - WHITELIST_SALE;
            uint256 _publicSaleSpendAmount = _spendAmount * _missingWhitelistTokens / _tigrisTokenAmount;
            whitelistSold += _tigrisTokenAmount - _missingWhitelistTokens;
            require(whitelistSold <= WHITELIST_SALE, "Whitelist sale reached cap");
            tigrisToken.safeTransfer(msg.sender, _tigrisTokenAmount - _missingWhitelistTokens);
            if (_buyPublicIfWhitelistSoldOut) {
                _handlePublicBuy(_publicSaleSpendAmount);
            } else {
                if (_publicSaleSpendAmount == _spendAmount) {
                    revert("Whitelist sale reached cap");
                }
                token.safeTransfer(msg.sender, _publicSaleSpendAmount);
            }
        } else {
            whitelistSold = whitelistSold + _tigrisTokenAmount;
            tigrisToken.safeTransfer(msg.sender, _tigrisTokenAmount);
        }
    }

    function _handlePublicBuy(uint256 _spendAmount) internal {
        require(PUBLIC_RAISE_GOAL > publicRaised, "Public sale reached cap");
        if (publicRaised + _spendAmount > PUBLIC_RAISE_GOAL) {
            uint256 _toRefund = publicRaised + _spendAmount - PUBLIC_RAISE_GOAL;
            _spendAmount = _spendAmount - _toRefund;
            if (_spendAmount == 0) {
                revert("Public sale reached cap");
            }
            token.safeTransfer(msg.sender, _toRefund);
        }
        publicRaised = publicRaised + _spendAmount;
        publicBuyerRaised[msg.sender] += _spendAmount;
    }

    function publicFinalPrice() public view returns (uint256 _finalPrice) {
        _finalPrice = publicRaised * 1e18 / PUBLIC_SALE;
        if (_finalPrice < PUBLIC_FLOOR_PRICE) {
            _finalPrice = PUBLIC_FLOOR_PRICE;
        }
    }

    function publicSaleAllocation(address _account) public view returns (uint256) {
        if (publicRaised == 0) {
            return 0;
        }
        if (publicFinalPrice() == PUBLIC_FLOOR_PRICE) {
            return publicBuyerRaised[_account] * 1e18 / PUBLIC_FLOOR_PRICE;
        }
        return PUBLIC_SALE * publicBuyerRaised[_account] / publicRaised;
    }
}
