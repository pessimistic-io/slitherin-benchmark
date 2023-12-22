// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./ERC20.sol";
import { TGE } from "./TGE.sol";
import { USDCMilestone, User } from "./Structs.sol";
import { ITGE } from "./ITGE.sol";
import { ITGEVault } from "./ITGEVault.sol";

///@notice this is a test contract

contract TGEVaultUSDC is ITGEVault {
    IERC20 public immutable usdcToken;
    ITGE public immutable tge;

    mapping(address => uint256) public usdcBalance;

    /***** EVENTS ***/
    event USDCDonated(address indexed user, uint256 amount, uint8 milestone);

    /*** ERRORS ***/

    error EventNotStarted();
    error DonationPaused();
    error AmountError();
    error USDCExceeded();
    error NotEnoughPEG();
    error TransferFailed();

    constructor(address _tge, address _usdc) {
        usdcToken = IERC20(_usdc);
        tge = ITGE(_tge);
    }

    function donate(uint256 amount) external override {
        if (amount == 0) revert AmountError();

        if (!tge.hasStarted()) revert EventNotStarted();
        if (tge.isDonationPaused()) revert DonationPaused();

        require(usdcToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");
        usdcBalance[msg.sender] += amount;

        uint8 currentMilestone = tge.currentUSDCMilestone(); ///@dev get specifc vault
        USDCMilestone memory usdcMilestone = tge.getUsdcMilestones(currentMilestone);

        if (usdcMilestone.USDCRaised + amount > usdcMilestone.USDCTarget && currentMilestone != 10) {
            uint256 excessAmount = (usdcMilestone.USDCRaised + amount) - usdcMilestone.USDCTarget;
            uint256 amountToDonate = usdcMilestone.USDCTarget - usdcMilestone.USDCRaised;

            tge.updateUSDCRaised(currentMilestone, amountToDonate);
            tge.updateUserUSDCdonations(currentMilestone, msg.sender, amountToDonate);

            uint256 userpegAllocationAmount = amountToDonate * usdcMilestone.priceOfPeg; //get current milestone price
            tge.updateUserUSDCpegAllocation(currentMilestone, msg.sender, userpegAllocationAmount);

            tge.updateMilestone();

            uint8 newMilestone = tge.currentUSDCMilestone();
            USDCMilestone memory newUSDCMilestone = tge.getUsdcMilestones(newMilestone);

            tge.updateUSDCRaised(newMilestone, excessAmount);
            tge.updateUserUSDCdonations(newMilestone, msg.sender, excessAmount);

            uint256 userpegAllocationExcess = excessAmount * newUSDCMilestone.priceOfPeg;
            tge.updateUserUSDCpegAllocation(newMilestone, msg.sender, userpegAllocationExcess);
        } else if (usdcMilestone.USDCRaised + amount > usdcMilestone.USDCTarget && currentMilestone == 10) {
            uint256 excessAmount = (usdcMilestone.USDCRaised + amount) - usdcMilestone.USDCTarget;
            uint256 amountToDonate = usdcMilestone.USDCTarget - usdcMilestone.USDCRaised;

            tge.updateUSDCRaised(currentMilestone, amountToDonate);
            tge.updateUserUSDCdonations(currentMilestone, msg.sender, amountToDonate);

            uint256 userpegAllocationAmount = amountToDonate * usdcMilestone.priceOfPeg; //get current milestone price
            tge.updateUserUSDCpegAllocation(currentMilestone, msg.sender, userpegAllocationAmount);

            tge.updateMilestone();
            //reimburse user
            require(usdcToken.transfer(msg.sender, excessAmount), "refund failed");
        } else {
            tge.updateUSDCRaised(currentMilestone, amount);
            tge.updateUserUSDCdonations(currentMilestone, msg.sender, amount);

            ///@dev calculate userpegAllocation for user Per milestone.
            uint256 userpegAllocation = (amount * usdcMilestone.priceOfPeg * 1e18) / 1e12; //get current milestone price
            tge.updateUserUSDCpegAllocation(currentMilestone, msg.sender, userpegAllocation);

            //update milestone
            tge.updateMilestone();
        }

        emit USDCDonated(msg.sender, amount, currentMilestone);
    }

    function withdraw() external override {
        uint256 userBalance = usdcBalance[msg.sender];
        require(userBalance != 0, "insuffient balance");
        usdcBalance[msg.sender] = 0;
        require(usdcToken.transfer(msg.sender, userBalance), "withdrawal failed");
    }
}

