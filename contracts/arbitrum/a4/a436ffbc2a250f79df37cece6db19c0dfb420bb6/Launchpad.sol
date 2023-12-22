// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Pausable.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IDeployer.sol";

contract LaunchPad is Ownable, Pausable, ReentrancyGuard, IEnums {
    //variables for oprating sale
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public startTime;
    uint256 public endOfWhitelistTime;
    uint256 public endTime;
    uint256 public endSaleTime;
    uint256 public listingRate;
    uint256 public presaleRate;
    uint256 public maxBuyPerParticipant;
    uint256 public minBuyPerParticipant;
    string public URIData;
    address public tokenSale;
    address public tokenPayment;
    address public admin;
    uint256 public adminTokenPaymentFee;
    uint256 public adminTokenSaleFee;
    bool public usingWhitelist;
    bool public refundWhenFinish = true;

    //variable for display data
    uint256 public totalDeposits;
    uint256 public totalRaised;
    uint256 public totalNeedToRaised;
    uint256 public contributorId;
    uint256 public status;
    IDeployer deployer;
    IEnums.LAUNCHPAD_TYPE launchPadType;
    mapping(address => uint256) public depositedAmount;
    mapping(address => uint256) public earnedAmount;
    mapping(uint256 => address) public contributorsList;
    mapping(address => bool) public whitelist;

    event userDeposit(uint256 amount, address user);
    event userRefunded(uint256 amount, address user);
    event userClaimed(uint256 amount, address user);
    event saleClosed(uint256 timeStamp, uint256 collectedAmount);
    event saleCanceled(uint256 timeStamp, address operator);

    constructor(
        uint256[2] memory _caps,
        uint256[3] memory _times,
        uint256[2] memory _rates,
        uint256[2] memory _limits,
        uint256[2] memory _adminFees,
        address[2] memory _tokens,
        string memory _URIData,
        address _admin,
        bool _refundWhenFinish,
        IEnums.LAUNCHPAD_TYPE _launchpadType
    ) {
        softCap = _caps[0];
        hardCap = _caps[1];
        startTime = _times[0];
        endTime = _times[1];
        endSaleTime = _times[2];
        URIData = _URIData;
        adminTokenSaleFee = _adminFees[0];
        adminTokenPaymentFee = _adminFees[1];
        tokenSale = _tokens[0];
        tokenPayment = _tokens[1];
        admin = _admin;
        presaleRate = _rates[0];
        listingRate = _rates[1];
        maxBuyPerParticipant = _limits[1];
        minBuyPerParticipant = _limits[0];
        refundWhenFinish = _refundWhenFinish;
        launchPadType = _launchpadType;
        deployer = IDeployer(msg.sender);
    }

    modifier restricted() {
        require(
            msg.sender == owner() || msg.sender == admin,
            "Launchpad: Caller not allowed"
        );
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Launchpad: Caller not admin");
        _;
    }

    function invest(uint256 _amount) external payable nonReentrant {
        _checkCanInvest(msg.sender);
        require(
            status == uint256(IEnums.LAUNCHPAD_STATE.OPENING),
            "Launchpad: Sale is not open"
        );
        require(startTime < block.timestamp, "Launchpad: Sale is not open yet");
        require(endTime > block.timestamp, "Launchpad: Sale is already closed");

        if (launchPadType == LAUNCHPAD_TYPE.NORMAL) {
            require(
                _amount + totalDeposits <= hardCap,
                "Launchpad(Normal): Hardcap reached"
            );
        }
        if (tokenPayment == address(0)) {
            require(_amount == msg.value, "Launchpad: Invalid payment amount");
        } else {
            IERC20(tokenPayment).transferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        if (depositedAmount[msg.sender] == 0) {
            contributorsList[contributorId] = msg.sender;
            contributorId++;
        }
        depositedAmount[msg.sender] += _amount;
        if (launchPadType == IEnums.LAUNCHPAD_TYPE.NORMAL) {
            require(
                depositedAmount[msg.sender] >= minBuyPerParticipant,
                "Launchpad: Min contribution not reached"
            );
            require(
                depositedAmount[msg.sender] <= maxBuyPerParticipant,
                "Launchpad: Max contribution not reached"
            );
            uint256 tokenRaised = (_amount *
                presaleRate *
                10**ERC20(tokenSale).decimals()) / 10**18;
            totalRaised += tokenRaised;
            totalNeedToRaised += tokenRaised;
            earnedAmount[msg.sender] += tokenRaised;
        }
        totalDeposits += _amount;
        deployer.addToUserLaunchpad(
            msg.sender,
            tokenSale,
            IEnums.LAUNCHPAD_TYPE.NORMAL
        );
        deployer.launchpadRaisedAmountChangedReport(tokenSale, totalDeposits, totalNeedToRaised);
        emit userDeposit(_amount, msg.sender);
    }

    function claimFund() external nonReentrant {
        _checkCanClaimFund();
        uint256 amountEarned = 0;
        if (launchPadType == LAUNCHPAD_TYPE.NORMAL) {
            amountEarned = earnedAmount[msg.sender];
            earnedAmount[msg.sender] = 0;
            if (totalNeedToRaised <= amountEarned) {
                totalNeedToRaised = 0;
            } else {
                totalNeedToRaised -= amountEarned;
            }
        } else {
            amountEarned =
                (depositedAmount[msg.sender] * getTotalTokenSale()) /
                totalDeposits;
            depositedAmount[msg.sender] = 0;
        }
        require(amountEarned > 0, "Launchpad: User have no token to claim");
        IERC20(tokenSale).transfer(msg.sender, amountEarned);
        deployer.launchpadRaisedAmountChangedReport(tokenSale, totalDeposits, totalNeedToRaised);
        emit userClaimed(amountEarned, msg.sender);
    }

    function claimRefund() external nonReentrant {
        if (status != uint256(IEnums.LAUNCHPAD_STATE.CANCELLED)) {
            _checkCanCancel();
        } else {
            require(
                status == uint256(IEnums.LAUNCHPAD_STATE.CANCELLED),
                "Launchpad: Sale must be cancelled"
            );
        }

        uint256 deposit = depositedAmount[msg.sender];
        require(deposit > 0, "Launchpad: User doesn't have deposits");
        depositedAmount[msg.sender] = 0;
        if (tokenPayment == address(0)) {
            payable(msg.sender).transfer(deposit);
        } else {
            IERC20(tokenPayment).transfer(msg.sender, deposit);
        }
        emit userRefunded(deposit, msg.sender);
    }

    function finishSale() external restricted nonReentrant {
        _checkCanFinish();
        status = uint256(IEnums.LAUNCHPAD_STATE.FINISHED);
        _ownerWithdraw();
        deployer.changeLaunchpadState(
            tokenSale,
            uint256(IEnums.LAUNCHPAD_STATE.FINISHED)
        );
        emit saleClosed(block.timestamp, totalDeposits);
    }

    function cancelSale() external restricted nonReentrant {
        _checkCanCancel();
        status = uint256(IEnums.LAUNCHPAD_STATE.CANCELLED);
        deployer.changeLaunchpadState(
            tokenSale,
            uint256(IEnums.LAUNCHPAD_STATE.CANCELLED)
        );
        IERC20(tokenSale).transfer(
            msg.sender,
            IERC20(tokenSale).balanceOf(address(this))
        );
        emit saleCanceled(block.timestamp, msg.sender);
    }

    function changeData(string memory _newData) external onlyOwner {
        URIData = _newData;
    }

    function enableWhitelist() external onlyOwner {
        require(usingWhitelist == false || (endOfWhitelistTime > 0 && block.timestamp > endOfWhitelistTime), "Whitelist mode is ongoing");
        usingWhitelist = true;
        endOfWhitelistTime = 0;
        deployer.changeActionChanged(address(this), usingWhitelist, endOfWhitelistTime);
    }

    function disableWhitelist(uint256 disableTime) external onlyOwner {
        require(usingWhitelist == true && (endOfWhitelistTime == 0 || block.timestamp < endOfWhitelistTime), "Whitelist mode is not ongoing");
        if (disableTime == 0) {
            usingWhitelist = false;
        } else {
            require(disableTime > block.timestamp);
            endOfWhitelistTime = disableTime;
        }
        deployer.changeActionChanged(address(this), usingWhitelist, endOfWhitelistTime);
    }

    function grantWhitelist(address[] calldata _users) external onlyOwner {
        address[] memory users = new address[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            if (!whitelist[_users[i]]) {
                whitelist[_users[i]] = true;
                users[i] = _users[i];
            }
        }
        deployer.changeWhitelistUsers(address(this), users, 0);
    }

    function revokeWhitelist(address[] calldata _users) external onlyOwner {
        address[] memory users = new address[](_users.length);
        for (uint256 i = 0; i < _users.length; i++) {
            if (whitelist[_users[i]]) {
                whitelist[_users[i]] = false;
                users[i] = _users[i];
            }
        }
        deployer.changeWhitelistUsers(address(this), users, 1);
    }

    function getContractInfo()
        external
        view
        returns (
            uint256[2] memory,
            uint256[3] memory,
            uint256[2] memory,
            uint256[2] memory,
            string memory,
            address,
            address,
            bool,
            uint256,
            uint256,
            bool,
            IEnums.LAUNCHPAD_TYPE
        )
    {
        return (
            [softCap, hardCap],
            [startTime, endTime, endSaleTime],
            [presaleRate, listingRate],
            [minBuyPerParticipant, maxBuyPerParticipant],
            URIData,
            tokenSale,
            tokenPayment,
            usingWhitelist,
            totalDeposits,
            status,
            refundWhenFinish,
            launchPadType
        );
    }

    function getContributorsList()
        external
        view
        returns (address[] memory list, uint256[] memory amounts)
    {
        list = new address[](contributorId);
        amounts = new uint256[](contributorId);

        for (uint256 i; i < contributorId; i++) {
            address userAddress = contributorsList[i];
            list[i] = userAddress;
            amounts[i] = depositedAmount[userAddress];
        }
    }

    function getTotalTokenSale() public view returns (uint256) {
        return
            (hardCap * presaleRate * 10**ERC20(tokenSale).decimals()) / 10**18;
    }

    function _ownerWithdraw() private {
        address DEAD_ADDRESS = 0x000000000000000000000000000000000000dEaD;
        uint256 balance;
        uint256 tokenSalefee;
        uint256 tokenPaymentfee;

        if (adminTokenSaleFee > 0) {
            tokenSalefee =
                ((
                    launchPadType == LAUNCHPAD_TYPE.NORMAL
                        ? totalRaised
                        : getTotalTokenSale()
                ) * adminTokenSaleFee) /
                10000;
        }
        if (tokenSalefee > 0) {
            IERC20(tokenSale).transfer(admin, tokenSalefee);
        }

        if (adminTokenPaymentFee > 0) {
            tokenPaymentfee = (totalDeposits * adminTokenPaymentFee) / 10000;
        }
        if (tokenPayment == address(0)) {
            balance = address(this).balance;
            payable(admin).transfer(tokenPaymentfee);
            payable(msg.sender).transfer(balance - tokenPaymentfee);
        } else {
            balance = IERC20(tokenPayment).balanceOf(address(this));
            IERC20(tokenPayment).transfer(admin, tokenPaymentfee);
            IERC20(tokenPayment).transfer(
                msg.sender,
                balance - tokenPaymentfee
            );
        }

        uint256 amountTokenSaleRemain = IERC20(tokenSale).balanceOf(
            address(this)
        );
        if (amountTokenSaleRemain > 0 && refundWhenFinish) {
            IERC20(tokenSale).transfer(msg.sender, amountTokenSaleRemain);
        }
        if (amountTokenSaleRemain > 0 && !refundWhenFinish) {
            IERC20(tokenSale).transfer(DEAD_ADDRESS, amountTokenSaleRemain);
        }
    }

    function _checkCanInvest(address _user) private view {
        // if (usingWhitelist && !whitelist[_user]) {
        //     require(
        //         endOfWhitelistTime > 0 && block.timestamp >= endOfWhitelistTime,
        //         "Launchpad: User can not invest"
        //     );
        // }
        require(
            usingWhitelist && (endOfWhitelistTime == 0 || block.timestamp < endOfWhitelistTime) && whitelist[_user] ||
            !usingWhitelist || usingWhitelist && endOfWhitelistTime > 0 && block.timestamp > endOfWhitelistTime,
            "Launchpad: User can not invest"
        );
    }

    function _checkCanFinish() private view {
        _checkCanClaimFund();
        if (
            launchPadType == LAUNCHPAD_TYPE.NORMAL &&
            block.timestamp < endSaleTime
        ) {
            require(
                totalNeedToRaised == 0,
                "Launchpad(Normal): All token sale need raised before end sale time"
            );
        }
        if (
            launchPadType == LAUNCHPAD_TYPE.FAIR &&
            block.timestamp < endSaleTime
        ) {
            require(
                ERC20(tokenSale).balanceOf(address(this)) <=
                    (getTotalTokenSale() * adminTokenSaleFee) / 10000,
                "Launchpad(Fair): All token sale need raised before end sale time"
            );
        }
    }

    function _checkCanClaimFund() private view {
        require(
            block.timestamp > endTime,
            "Launchpad: Finishing launchpad does not available now"
        );
        require(
            status == uint256(IEnums.LAUNCHPAD_STATE.OPENING),
            "Launchpad: Sale is already finished or cancelled"
        );
        if (launchPadType == LAUNCHPAD_TYPE.NORMAL) {
            require(
                totalDeposits >= softCap,
                "Launchpad(Normal): Soft cap not reached"
            );
        } else {
            require(
                totalDeposits >= hardCap,
                "Launchpad(Fair): Cap not reached"
            );
        }
    }

    function _checkCanCancel() private view {
        require(
            status == uint256(IEnums.LAUNCHPAD_STATE.OPENING),
            "Launchpad: Sale is already finished or cancelled"
        );
        if (launchPadType == IEnums.LAUNCHPAD_TYPE.NORMAL) {
            require(
                totalDeposits < softCap,
                "Launchpad(Normal): Soft cap reached"
            );
        } else {
            require(totalDeposits < hardCap, "Launchpad(Fair): Cap reached");
        }
    }
}

