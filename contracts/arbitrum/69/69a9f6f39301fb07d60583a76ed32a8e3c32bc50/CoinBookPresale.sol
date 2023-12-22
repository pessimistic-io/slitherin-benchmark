// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import { ReentrancyGuardUpgradeable }      from "./ReentrancyGuardUpgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { SafeERC20Upgradeable as SafeERC20, IERC20Upgradeable as IERC20 }      from "./SafeERC20Upgradeable.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { ICoinBookPresale } from "./ICoinBookPresale.sol";

contract CoinBookPresale is ICoinBookPresale, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    address public wETH;
    IERC20 public usdc;
    IERC20 public book;
    ISwapRouter public sushi;
    uint256 private constant A_FACTOR = 10**18;

    PresaleInfo private whitelistSaleInfo;
    PresaleInfo private publicSaleInfo;
    uint80 public claimStart;
    bool private contractFunded;
    bool public presaleFinalized;

    uint256 public usersInWhitelist;
    uint256 public usersInPublic;

    mapping(address => UserInfo) public contributerInfo;
    mapping(address => bool) public isWhitelisted;

    modifier claimable() {
        require(
            contributerInfo[msg.sender].wlContributed > 0 ||
                contributerInfo[msg.sender].psContributed > 0,
            "User did not participate"
        );
        require(!contributerInfo[msg.sender].claimed, "User already claimed");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external override payable {
        require(msg.sender == wETH || msg.sender == owner(), "Caller not allowed");
        emit Received(msg.sender, msg.value);
    }

    function initialize(
        uint256 _wlTarget,
        uint256 _wlSaleAmount,
        uint256 _psTarget,
        uint256 _psSaleAmount
    ) external reinitializer(2) {
       
        whitelistSaleInfo.target = _wlTarget;
        whitelistSaleInfo.saleAmount = _wlSaleAmount;

        publicSaleInfo.target = _psTarget;
        publicSaleInfo.saleAmount = _psSaleAmount;
    }

    function contributeInWhitelist(uint256 _amount) external override nonReentrant {
        require(isWhitelisted[msg.sender], "User not whitelisted");
        require(_presaleStatus() == 1, "Whitelist Presale not active");
        require(_amount > 0, "Contribution must be more than 0");
        require(
            _amount + contributerInfo[msg.sender].wlContributed <= whitelistSaleInfo.maxSpend, 
            "Contribution exceeds maxSpend"
        );

        if (contributerInfo[msg.sender].wlContributed == 0) {
            usersInWhitelist++;
        }
        contributerInfo[msg.sender].wlContributed += _amount;
        whitelistSaleInfo.raisedAmount += _amount;

        usdc.safeTransferFrom(msg.sender, address(this), _amount);

        emit Contributed(msg.sender, _amount, "Whitelist Sale", block.timestamp);
    }

    function swapAndContributeInWhitelist(uint256 minAmount) external payable override nonReentrant {
        require(isWhitelisted[msg.sender], "User not whitelisted");
        require(_presaleStatus() == 1, "Whitelist Presale not active");
        require(msg.value > 0, "Contribution must be more than 0");

        address[] memory path = new address[](2);
        path[0] = wETH;
        path[1] = address(usdc);
        uint256 swapAmt = msg.value;
        uint256 minOut = minAmount;
        uint256[] memory amounts = sushi.swapExactETHForTokens{
                value: swapAmt
            }(
                minOut, 
                path, 
                address(this), 
                block.timestamp
            );

        uint256 _amount = amounts[1];

        require(
            _amount + contributerInfo[msg.sender].wlContributed <= whitelistSaleInfo.maxSpend, 
            "Contribution exceeds maxSpend"
        );

        if (contributerInfo[msg.sender].wlContributed == 0) {
            usersInWhitelist++;
        }
        contributerInfo[msg.sender].wlContributed += _amount;
        whitelistSaleInfo.raisedAmount += _amount;

        emit SwappedToUSDC(msg.sender, swapAmt, _amount);
        emit Contributed(msg.sender, _amount, "Whitelist Sale", block.timestamp);
    }

    function contributeInPublic(uint256 _amount) external override nonReentrant {
        require(_presaleStatus() == 3, "Public Presale not active");
        require(_amount > 0, "Contribution must be more than 0");
        require(
            _amount + contributerInfo[msg.sender].psContributed <= publicSaleInfo.maxSpend, 
            "Contribution exceeds maxSpend"
        );

        if (contributerInfo[msg.sender].psContributed == 0) {
            usersInPublic++;
        }
        contributerInfo[msg.sender].psContributed += _amount;
        publicSaleInfo.raisedAmount += _amount;

        usdc.safeTransferFrom(msg.sender, address(this), _amount);

        emit Contributed(msg.sender, _amount, "Public Sale", block.timestamp);
    }

    function swapAndContributeInPublic(uint256 minAmount) external payable override nonReentrant {
        require(_presaleStatus() == 3, "Public Presale not active");
        require(msg.value > 0, "Contribution must be more than 0");

        address[] memory path = new address[](2);
        path[0] = wETH;
        path[1] = address(usdc);
        uint256 swapAmt = msg.value;
        uint256 minOut = minAmount;
        uint256[] memory amounts = sushi.swapExactETHForTokens{
                value: swapAmt
            }(
                minOut, 
                path, 
                address(this), 
                block.timestamp
            );

        uint256 _amount = amounts[1];

        require(
            _amount + contributerInfo[msg.sender].psContributed <= publicSaleInfo.maxSpend, 
            "Contribution exceeds maxSpend"
        );

        if (contributerInfo[msg.sender].psContributed == 0) {
            usersInPublic++;
        }
        contributerInfo[msg.sender].psContributed += _amount;
        publicSaleInfo.raisedAmount += _amount;

        emit SwappedToUSDC(msg.sender, swapAmt, _amount);
        emit Contributed(msg.sender, _amount, "Public Sale", block.timestamp);
    }

    function claimBook() external override nonReentrant claimable {
        (uint256 wlBook, uint256 wlRefund, uint256 psBook, uint256 psRefund) = _getClaimableAmounts(msg.sender);
        uint256 bookOwed = wlBook + psBook;
        uint256 refundOwed;
        if (contributerInfo[msg.sender].wlRefunded > 0) {
            refundOwed = psRefund;
        } else {
            refundOwed = wlRefund + psRefund;
            contributerInfo[msg.sender].wlRefunded = wlRefund;
        }

        contributerInfo[msg.sender].wlClaimed = wlBook;
        contributerInfo[msg.sender].psClaimed = psBook;
        contributerInfo[msg.sender].psRefunded = psRefund;
        contributerInfo[msg.sender].claimed = true;

        book.safeTransfer(msg.sender, bookOwed);
        if (refundOwed > 0) {
            usdc.safeTransfer(msg.sender, refundOwed);
        }

        emit Claimed(msg.sender, bookOwed, refundOwed, wlBook, psBook, wlRefund, psRefund, block.timestamp);
    }

    function claimExcessWhitelist(bool moveToPublic) external override nonReentrant {
        require(_presaleStatus() == 3, "Public Presale not active");

        (, uint256 wlRefund,,) = _getClaimableAmounts(msg.sender);
        if (wlRefund == 0) { return; }

        uint256 _amount;
        uint256 _refund;
        if (moveToPublic) {
            if (wlRefund + contributerInfo[msg.sender].psContributed <= publicSaleInfo.maxSpend) {
                _amount = wlRefund;
            } else if (contributerInfo[msg.sender].psContributed <= publicSaleInfo.maxSpend) {
                _amount = publicSaleInfo.maxSpend - contributerInfo[msg.sender].psContributed;
                _refund = wlRefund - _amount;
            } else {
                _refund = wlRefund;
            }

            if (contributerInfo[msg.sender].psContributed == 0) {
                usersInPublic++;
            }
            contributerInfo[msg.sender].psContributed += _amount;
            publicSaleInfo.raisedAmount += _amount;

            if (_refund > 0) { 
                usdc.safeTransfer(msg.sender, _refund); 
            }

            emit Contributed(msg.sender, _amount, "Public Sale", block.timestamp);
        } else {
            _refund = wlRefund;
            usdc.safeTransfer(msg.sender, _refund);
        }
        contributerInfo[msg.sender].wlRefunded = wlRefund;
    }

    function fundContract() external override nonReentrant onlyOwner {
        require(!contractFunded, "Contract already funded");
        uint256 fundAmount = whitelistSaleInfo.saleAmount + publicSaleInfo.saleAmount;
        book.safeTransferFrom(msg.sender, address(this), fundAmount);
        contractFunded = true;
    }

    function finalizePresale() external override nonReentrant onlyOwner {
        require(_presaleStatus() >= 4, "Public Sale has not ended");
        require(!presaleFinalized, "Presale already finalized");        

        uint256 collectableUSDC;
        if (whitelistSaleInfo.raisedAmount > whitelistSaleInfo.target) {
            collectableUSDC += whitelistSaleInfo.target;
        } else {
            collectableUSDC += whitelistSaleInfo.raisedAmount;
        }
        if (publicSaleInfo.raisedAmount > publicSaleInfo.target) {
            collectableUSDC += publicSaleInfo.target;
        } else {
            collectableUSDC += publicSaleInfo.raisedAmount;
        }
        usdc.safeTransfer(owner(), collectableUSDC);

        uint256 excessBook;
        if (whitelistSaleInfo.raisedAmount < whitelistSaleInfo.target) {
            excessBook += whitelistSaleInfo.saleAmount - (
                (((whitelistSaleInfo.raisedAmount * A_FACTOR) / whitelistSaleInfo.target) * 
                    whitelistSaleInfo.saleAmount) / A_FACTOR
            );
        }
        if (publicSaleInfo.raisedAmount < publicSaleInfo.target) {
            excessBook += publicSaleInfo.saleAmount - (
                (((publicSaleInfo.raisedAmount * A_FACTOR) / publicSaleInfo.target) * 
                    publicSaleInfo.saleAmount) / A_FACTOR
            );
        }
        if (excessBook > 0) {
            book.safeTransfer(owner(), excessBook);
        }

        (uint256 t, uint256 w, uint256 p) = _getAmountsRaised();

        presaleFinalized = true;
        emit PresaleFinalized(t, w, p, collectableUSDC, excessBook, block.timestamp);
    }

    function extendTimes(
        uint80 _wlStart, 
        uint80 _wlEnd, 
        uint80 _psStart, 
        uint80 _psEnd, 
        uint80 _claimStart
    ) external override onlyOwner {
        require(
            _wlEnd > _wlStart && 
                _psStart > _wlEnd && 
                _psEnd > _psStart && 
                _claimStart > _psEnd, 
            "Conflicting timeline"
        );
        whitelistSaleInfo.startTime = _wlStart;
        whitelistSaleInfo.endTime = _wlEnd;

        publicSaleInfo.startTime = _psStart;
        publicSaleInfo.endTime = _psEnd;

        claimStart = _claimStart;

        emit TimesExtended(_wlStart, _wlEnd, _psStart, _psEnd, _claimStart);
    }

    function updateManyWhitelist(address[] calldata _users, bool _flag) external override onlyOwner {
        for (uint i = 0; i < _users.length; i++) {
            isWhitelisted[_users[i]] = _flag;
        }
        emit UpdatedManyWhitelist(_users, _flag);
    }

    function updateSingleWhitelist(address _user, bool _flag) external override onlyOwner {
        isWhitelisted[_user] = _flag;
        emit UpdatedSingleWhitelist(_user, _flag);
    }

    function getAmountsRaised() external view override returns (
        uint256 totalRaised, 
        uint256 whitelistRaised, 
        uint256 publicRaised
    ) {
        return _getAmountsRaised();
    }

    function getPresaleStatus() external view override returns (uint8 status) {
        return _presaleStatus();
    }

    function getClaimableAmounts(
        address _user
    ) external view override returns (
        uint256 wlBook, 
        uint256 wlRefund, 
        uint256 psBook, 
        uint256 psRefund
    ) {
        return _getClaimableAmounts(_user);
    }

    function getWhitelistSaleInfo() external view override returns (
        uint80 startTime,
    	uint80 endTime,
    	uint256 maxSpend,
    	uint256 target,
    	uint256 saleAmount,
    	uint256 raisedAmount
    ) {
        startTime = whitelistSaleInfo.startTime;
        endTime = whitelistSaleInfo.endTime;
    	maxSpend = whitelistSaleInfo.maxSpend;
    	target = whitelistSaleInfo.target;
    	saleAmount = whitelistSaleInfo.saleAmount;
    	raisedAmount = whitelistSaleInfo.raisedAmount;
    }

    function getPublicSaleInfo() external view override returns (
        uint80 startTime,
    	uint80 endTime,
    	uint256 maxSpend,
    	uint256 target,
    	uint256 saleAmount,
    	uint256 raisedAmount
    ) {
        startTime = publicSaleInfo.startTime;
        endTime = publicSaleInfo.endTime;
    	maxSpend = publicSaleInfo.maxSpend;
    	target = publicSaleInfo.target;
    	saleAmount = publicSaleInfo.saleAmount;
    	raisedAmount = publicSaleInfo.raisedAmount;
    }

    function _getClaimableAmounts(
        address _user
    ) internal view returns (
        uint256 wlBook, 
        uint256 wlRefund, 
        uint256 psBook, 
        uint256 psRefund
    ) {
        UserInfo memory user = contributerInfo[_user];
        if (user.wlContributed > 0) {
            uint256 userRateWL = ((user.wlContributed * A_FACTOR) / whitelistSaleInfo.raisedAmount);
            uint256 refundRateWL = ((whitelistSaleInfo.target * A_FACTOR) / whitelistSaleInfo.raisedAmount);
            if (whitelistSaleInfo.raisedAmount > whitelistSaleInfo.target) {
                wlBook = ((userRateWL * whitelistSaleInfo.saleAmount) / A_FACTOR);
                wlRefund = user.wlRefunded == 0 ? 
                    user.wlContributed - ((refundRateWL * user.wlContributed) / A_FACTOR) : 0;
            } else {
                uint256 adjustedBookWL = (
                    (((whitelistSaleInfo.raisedAmount * A_FACTOR) / whitelistSaleInfo.target) * 
                        whitelistSaleInfo.saleAmount) / A_FACTOR
                );
                wlBook = ((userRateWL * adjustedBookWL) / A_FACTOR);
                wlRefund = 0;
            }
        }

        if (user.psContributed > 0) {
            uint256 userRatePS = ((user.psContributed * A_FACTOR) / publicSaleInfo.raisedAmount);
            uint256 refundRatePS = ((publicSaleInfo.target * A_FACTOR) / publicSaleInfo.raisedAmount);
            if (publicSaleInfo.raisedAmount > publicSaleInfo.target) {
                psBook = ((userRatePS * publicSaleInfo.saleAmount) / A_FACTOR);
                psRefund = user.psContributed - ((refundRatePS * user.psContributed) / A_FACTOR);
            } else {
                uint256 adjustedBookPS = (
                    (((publicSaleInfo.raisedAmount * A_FACTOR) / publicSaleInfo.target) * 
                        publicSaleInfo.saleAmount) / A_FACTOR
                );
                psBook = ((userRatePS * adjustedBookPS) / A_FACTOR);
                psRefund = 0;
            }
        }
    }

    function _getAmountsRaised() internal view returns (
        uint256 totalRaised, 
        uint256 whitelistRaised, 
        uint256 publicRaised
    ) {
        whitelistRaised = whitelistSaleInfo.raisedAmount;
        publicRaised = publicSaleInfo.raisedAmount;
        totalRaised = whitelistRaised + publicRaised;
    }

    function _presaleStatus() internal view returns (uint8 status) {
        if (!contractFunded) {
            return 99; // Contract has not been funded with Book tokens
        }
        if (block.timestamp >= claimStart) {
            return 5; // Presale is claimable
        }
        if (block.timestamp > publicSaleInfo.endTime) {
            return 4; // All Presale rounds have ended and awaiting claimStart
        }
        if (block.timestamp >= publicSaleInfo.startTime) {
            return 3; // Public Sale is active
        }
        if (block.timestamp > whitelistSaleInfo.endTime) {
            return 2; // Whitelist Sale has ended, awaiting start of Public Sale
        }
        if (block.timestamp >= whitelistSaleInfo.startTime) {
            return 1; // Whitelist Sale is active
        }
        if (block.timestamp < whitelistSaleInfo.startTime) {
            return 0; // Awaiting start of Whitelist Sale
        }
    }
}

