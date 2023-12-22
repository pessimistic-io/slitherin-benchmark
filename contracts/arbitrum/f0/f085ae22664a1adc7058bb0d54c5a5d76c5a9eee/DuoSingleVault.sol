// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./IDuoMaster.sol";

contract DuoSingleVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public duo;

    IDuoMaster public duoMaster;

    uint256 public duoSinglePid;

    bool public isInitialized;

    uint256 public totalShares;

    mapping(address => uint256) public userShares;

    mapping(address => uint256) public userPrincipal;

    bool public isReinvesting = true;

    uint256 performanceFee = 200; // 2%

    uint256 feeDenominator = 10000;

    address public feeAddress;

    constructor() {}

    function initialize(
        IERC20 _duo,
        IDuoMaster _duoMaster,
        uint256 _duoSinglePid
    ) external onlyOwner {
        require(!isInitialized, "DuoSingleVault: already initialized");
        require(
            address(_duo) != address(0),
            "DuoSingleVault: duo is the zero address"
        );
        require(
            address(_duoMaster) != address(0),
            "DuoSingleVault: duoMaster is the zero address"
        );
        isInitialized = true;
        duo = _duo;
        duoMaster = _duoMaster;
        duoSinglePid = _duoSinglePid;
        feeAddress = msg.sender;

        duo.safeApprove(address(duoMaster), type(uint256).max);
    }

    function _reinvest() internal {
        if (!isReinvesting) {
            return;
        }
        try duoMaster.pendingEarnings(duoSinglePid, address(this)) returns (
            uint256
        ) {} catch {
            return;
        }

        duoMaster.harvest(duoSinglePid, address(this));

        uint256 duoBalance = duo.balanceOf(address(this));

        if (duoBalance == 0) {
            return;
        }

        uint256 fee = (duoBalance * performanceFee) / feeDenominator;

        duo.safeTransfer(feeAddress, fee);

        duoMaster.deposit(
            duoSinglePid,
            duoBalance - fee,
            address(this),
            address(0)
        );
    }

    function reinvest() external {
        _reinvest();
    }

    function depositAll() public {
        deposit(duo.balanceOf(msg.sender));
    }

    function withdrawAll() public {
        withdraw(userShares[msg.sender]);
    }

    function deposit(uint256 _amount) public nonReentrant {
        _reinvest();

        duo.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 sharesToAdd = amountToShares(_amount);

        duoMaster.deposit(duoSinglePid, _amount, address(this), address(0));

        userShares[msg.sender] += sharesToAdd;
        totalShares += sharesToAdd;

        userPrincipal[msg.sender] = sharesToAmount(userShares[msg.sender]);
    }

    function withdrawByAmount(uint256 _amount) public nonReentrant {
        _reinvest();

        uint256 shares = amountToShares(_amount);

        require(
            userShares[msg.sender] >= shares,
            "DuoSingleVault: not enough shares"
        );

        duoMaster.withdraw(duoSinglePid, _amount, address(this));

        duo.safeTransfer(msg.sender, _amount);

        userShares[msg.sender] -= shares;
        totalShares -= shares;

        userPrincipal[msg.sender] = sharesToAmount(userShares[msg.sender]);
    }

    function withdraw(uint256 _shares) public nonReentrant {
        _reinvest();

        uint256 amountToWithdraw = sharesToAmount(_shares);

        require(
            userShares[msg.sender] >= _shares,
            "DuoSingleVault: not enough shares"
        );

        duoMaster.withdraw(duoSinglePid, amountToWithdraw, address(this));

        duo.safeTransfer(msg.sender, amountToWithdraw);

        userShares[msg.sender] -= _shares;
        totalShares -= _shares;

        userPrincipal[msg.sender] = sharesToAmount(userShares[msg.sender]);
    }

    function amountToShares(uint256 _amount) public view returns (uint256) {
        (uint256 staked, , ) = duoMaster.userInfo(duoSinglePid, address(this));
        uint256 shares;
        if (totalShares == 0) {
            shares = _amount;
        } else {
            shares = (_amount * totalShares) / staked;
        }

        return shares;
    }

    function sharesToAmount(uint256 _shares) public view returns (uint256) {
        (uint256 staked, , ) = duoMaster.userInfo(duoSinglePid, address(this));
        uint256 amount;
        if (staked == 0) {
            amount = _shares;
        } else {
            amount = (_shares * staked) / totalShares;
        }

        return amount;
    }

    function checkReward() public view returns (uint256) {
        return duoMaster.pendingEarnings(duoSinglePid, address(this));
    }

    function userInfo(
        address _user
    )
        external
        view
        returns (uint256 _principal, uint256 _shares, uint256 _earned)
    {
        return (
            sharesToAmount(userShares[_user]),
            userShares[_user],
            sharesToAmount(userShares[_user]) - userPrincipal[_user]
        );
    }

    function setReinvesting(bool _isReinvesting) external onlyOwner {
        isReinvesting = _isReinvesting;
    }

    function totalSupply() external view returns (uint256) {
        return totalShares;
    }

    function balance() external view returns (uint256) {
        (uint256 staked, , ) = duoMaster.userInfo(duoSinglePid, address(this));
        return staked;
    }

    function balanceOf(address _account) external view returns (uint256) {
        return sharesToAmount(userShares[_account]);
    }

    function setPerformanceFee(uint256 _performanceFee) external onlyOwner {
        require(
            _performanceFee <= feeDenominator,
            "DuoSingleVault: performance fee cannot be more than 100%"
        );
        performanceFee = _performanceFee;
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
    }
}

