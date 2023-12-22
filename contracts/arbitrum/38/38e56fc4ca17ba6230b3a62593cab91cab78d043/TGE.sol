//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { PriceCalculator } from "./PriceCalculator.sol";
import { IERC20 } from "./IERC20.sol";
import { ITGE } from "./ITGE.sol";
import { User, Milestone } from "./Structs.sol";

contract TGE is ITGE, Ownable {
    using PriceCalculator for uint256;

    uint8 public constant MAX_MILESTONE = 10; ///@dev total milestones
    IERC20 public immutable usdcToken;
    IERC20 public immutable plsToken;

    enum DonationType {
        USDC,
        PLS
    }

    uint8 public currentMilestone;
    bool public hasStarted;
    bool public isPaused;

    mapping(uint8 => Milestone) public milestones;
    mapping(address => mapping(uint8 => bool)) public donatedInMilestone;
    mapping(address => mapping(uint8 => uint256 index)) private userIndex;
    mapping(uint8 => User[]) public users; ///@dev returns users who donated in a milestone
    mapping(address => bool) public userBlacklisted;

    event MilestoneAchieved(uint8 indexed milestone, uint256 indexed targetAchieved);
    event PausedDonation(bool isPaused);
    event SaleStarted(bool hasStarted);
    event USDCDonated(address indexed user, uint8 indexed milestone, uint256 amount);
    event PLSDonated(address user, uint8 indexed milestone, uint256 amount);
    event RefundedExcess(address indexed user, address indexed token, uint256 amountRefunded);

    constructor(address usdc, address pls) {
        usdcToken = IERC20(usdc);
        plsToken = IERC20(pls);

        currentMilestone = 1;

        milestones[1] = Milestone({
            priceOfPeg: 5e5,
            usdcRaised: 0,
            usdcOfPlsRaised: 0,
            plsRaised: 0,
            targetAmount: 10e6, //200_000e6,
            totalUSDCRaised: 0,
            milestoneId: 1,
            isCleared: false
        });
    }

    function donateUSDC(uint256 amount) public override {
        require(hasStarted, "Too soon");
        require(!isPaused, "Paused");
        require(amount != 0, "Invalid amount");
        if (currentMilestone == MAX_MILESTONE && milestones[currentMilestone].isCleared) revert("Sold out");
        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");

        _donateUSDC(amount);
    }

    function donatePLS(uint256 amount) public override {
        require(hasStarted, "Too soon");
        require(!isPaused, "Paused");
        require(amount != 0, "Invalid amount");
        if (currentMilestone == MAX_MILESTONE && milestones[currentMilestone].isCleared) revert("Sold out");
        require(plsToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");

        _donatePLS(amount);
    }

    function _donateUSDC(uint256 amount) private {
        Milestone memory _currentMilestone = milestones[currentMilestone];

        if (_currentMilestone.totalUSDCRaised + amount > _currentMilestone.targetAmount) {
            uint256 amountToDonate = _currentMilestone.targetAmount - _currentMilestone.totalUSDCRaised;
            uint256 excessUSDC = (_currentMilestone.totalUSDCRaised + amount) - _currentMilestone.targetAmount;

            milestones[currentMilestone].usdcRaised += amountToDonate;
            milestones[currentMilestone].totalUSDCRaised += amountToDonate;

            updateUserDonations(DonationType.USDC, amountToDonate, 0);
            emit USDCDonated(msg.sender, currentMilestone, amountToDonate);

            updateMilestone();

            if (_currentMilestone.milestoneId == MAX_MILESTONE) {
                require(usdcToken.transfer(msg.sender, excessUSDC), "refund failed");
                emit RefundedExcess(msg.sender, address(usdcToken), excessUSDC);
            } else {
                _donateUSDC(excessUSDC);
            }
        } else {
            milestones[currentMilestone].usdcRaised += amount;
            milestones[currentMilestone].totalUSDCRaised += amount;

            updateUserDonations(DonationType.USDC, amount, 0);
            emit USDCDonated(msg.sender, currentMilestone, amount);

            updateMilestone();
        }
    }

    function _donatePLS(uint256 amount) private {
        uint256 amountInUSDC = amount.getPlsInUSDC();
        Milestone memory _currentMilestone = milestones[currentMilestone];

        if (_currentMilestone.totalUSDCRaised + amountInUSDC > _currentMilestone.targetAmount) {
            uint256 amountOfUsdcToDonate = _currentMilestone.targetAmount - _currentMilestone.totalUSDCRaised;
            uint256 amountOfPlsToDonate = (amountOfUsdcToDonate * amount) / amountInUSDC;
            uint256 excessPLS = amount - amountOfPlsToDonate;

            milestones[currentMilestone].usdcOfPlsRaised += amountOfUsdcToDonate;
            milestones[currentMilestone].totalUSDCRaised += amountOfUsdcToDonate;
            milestones[currentMilestone].plsRaised += amountOfPlsToDonate;

            updateUserDonations(DonationType.PLS, amountOfUsdcToDonate, amountOfPlsToDonate);
            emit PLSDonated(msg.sender, currentMilestone, amountOfPlsToDonate);

            updateMilestone();

            if (_currentMilestone.milestoneId == MAX_MILESTONE) {
                require(plsToken.transfer(msg.sender, excessPLS), "refund failed");
                emit RefundedExcess(msg.sender, address(plsToken), excessPLS);
            } else {
                _donatePLS(excessPLS);
            }
        } else {
            milestones[currentMilestone].usdcOfPlsRaised += amountInUSDC;
            milestones[currentMilestone].totalUSDCRaised += amountInUSDC;
            milestones[currentMilestone].plsRaised += amount;

            updateUserDonations(DonationType.PLS, amountInUSDC, amount);
            emit PLSDonated(msg.sender, currentMilestone, amount);

            updateMilestone();
        }
    }

    function updateMilestone() private {
        Milestone memory _currentMilestone = milestones[currentMilestone];
        if (_currentMilestone.totalUSDCRaised == _currentMilestone.targetAmount) {
            milestones[currentMilestone].isCleared = true;

            if (currentMilestone != MAX_MILESTONE) {
                uint8 previousMilestone = currentMilestone;
                uint8 newMilestoneId = ++currentMilestone;
                uint256 newMilestoneTarget = _currentMilestone.targetAmount + 1e6; //+ 40_000e6;

                milestones[newMilestoneId] = Milestone({
                    priceOfPeg: _currentMilestone.priceOfPeg + 1e5,
                    usdcRaised: 0,
                    usdcOfPlsRaised: 0,
                    plsRaised: 0,
                    targetAmount: newMilestoneTarget,
                    totalUSDCRaised: 0,
                    milestoneId: newMilestoneId,
                    isCleared: false
                });

                emit MilestoneAchieved(previousMilestone, _currentMilestone.totalUSDCRaised);
            }
        }
    }

    function updateUserDonations(DonationType donation, uint256 usdcAmount, uint256 plsAmount) private {
        if (donatedInMilestone[msg.sender][currentMilestone]) {
            uint256 index = userIndex[msg.sender][currentMilestone];

            if (donation == DonationType.USDC) {
                users[currentMilestone][index].usdcDonations += usdcAmount;
            } else {
                users[currentMilestone][index].usdcOfPlsDonations += usdcAmount;
                users[currentMilestone][index].plsDonations += plsAmount;
            }
        } else {
            donatedInMilestone[msg.sender][currentMilestone] = true;
            uint256 index = users[currentMilestone].length; //basically a push operation
            userIndex[msg.sender][currentMilestone] = index;

            if (donation == DonationType.USDC) {
                User memory newUser = User({
                    user: msg.sender,
                    plsDonations: 0,
                    usdcOfPlsDonations: 0,
                    usdcDonations: usdcAmount
                });

                users[currentMilestone].push(newUser);
            } else {
                User memory newUser = User({
                    user: msg.sender,
                    plsDonations: plsAmount,
                    usdcOfPlsDonations: usdcAmount,
                    usdcDonations: 0
                });
                users[currentMilestone].push(newUser);
            }
        }
    }

    function startSale() public override onlyOwner {
        hasStarted = true;

        emit SaleStarted(hasStarted);
    }

    function stopSale() public override onlyOwner {
        hasStarted = false;
        emit SaleStarted(hasStarted);
    }

    function pauseDonation() public override onlyOwner {
        isPaused = true;

        emit PausedDonation(isPaused);
    }

    function unPauseDonation() public override onlyOwner {
        if (isPaused) {
            isPaused = false;
        }
        emit PausedDonation(isPaused);
    }

    function getUserDetails(address user) public view override returns (User memory) {
        User memory userDetails;
        userDetails.user = user;
        for (uint8 i = 1; i <= currentMilestone; ++i) {
            uint256 _userIndex = userIndex[user][i];
            User[] memory _users = users[i];
            User memory userWanted = _users[_userIndex];

            userDetails.plsDonations += userWanted.plsDonations;
            userDetails.usdcDonations += userWanted.usdcDonations;
            userDetails.usdcOfPlsDonations += userWanted.usdcOfPlsDonations;
        }
        return userDetails;
    }

    function getUsersPerMilestone(uint8 milestone) public view override returns (User[] memory) {
        return users[milestone];
    }

    function withdrawUSDC() external override onlyOwner {
        uint256 usdcBalance = IERC20(usdcToken).balanceOf(address(this));
        require(usdcBalance != 0, "zero usdc balance");
        require(usdcToken.transfer(owner(), usdcBalance), "usdc withdrawal failed");
    }

    function withdrawPLS() external override onlyOwner {
        uint256 plsBalance = IERC20(plsToken).balanceOf(address(this));
        require(plsBalance != 0, "zero pls balance");
        require(plsToken.transfer(owner(), plsBalance), "pls withdrawal failed");
    }
}

