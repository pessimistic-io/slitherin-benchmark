// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";
import { TGE } from "./TGE.sol";
import { PriceCalculator } from "./PriceCalculator.sol";
import { PLSMilestone, User } from "./Structs.sol";
import { ITGE } from "./ITGE.sol";
import { ITGEVault } from "./ITGEVault.sol";

///@notice this is a test contract

contract TGEVaultPLS is ITGEVault, Ownable {
    using PriceCalculator for uint256;

    ITGE public immutable tge;
    IERC20 public immutable plsToken;

    mapping(address => uint256) public plsBalance;

    /***** EVENTS ***/
    event PLSDonated(address user, uint amount, uint milestone);

    /*** ERRORS ***/
    error MilestoneCleared();
    error EventNotStarted();
    error DonationPaused();
    error AmountError();
    error PLSExceeded();
    error TransferFailed();
    error NotEnoughPEG();

    constructor(address _tge, address _pls) {
        plsToken = IERC20(_pls);
        tge = ITGE(_tge);
    }

    /** @notice donate amount in PLS
     * @dev converts PLS to USDC.
     * @param amount -> amountInPls
     */

    function donate(uint256 amount) external override {
        if (amount == 0) revert AmountError();
        if (!tge.hasStarted()) revert EventNotStarted();
        if (tge.isDonationPaused()) revert DonationPaused();

        require(plsToken.transferFrom(msg.sender, address(this), amount), "Transfer Failed");

        ///@notice for testing
        plsBalance[msg.sender] += amount;

        uint256 amountInUSDC = amount.getPlsInUSDC();

        uint8 currentMilestone = tge.currentPLSMilestone(); ///@dev get specifc vault
        PLSMilestone memory plsMilestone = tge.getPlsMilestones(currentMilestone);

        if (plsMilestone.USDCOfPlsRaised + amountInUSDC > plsMilestone.USDCOfPlsTarget && currentMilestone != 10) {
            uint256 excessAmount = (plsMilestone.USDCOfPlsRaised + amountInUSDC) - plsMilestone.USDCOfPlsTarget;
            uint256 amountToDonate = plsMilestone.USDCOfPlsTarget - plsMilestone.USDCOfPlsRaised;
            uint256 amountOfPls = (amountToDonate * amount) / amountInUSDC;

            tge.updatePLSRaised(currentMilestone, amountToDonate, amountOfPls);
            tge.updateUserPLSdonations(currentMilestone, msg.sender, amountToDonate);

            uint256 userpegAllocationAmount = amountToDonate * plsMilestone.priceOfPeg; //get current milestone price
            tge.updateUserPLSpegAllocation(currentMilestone, msg.sender, userpegAllocationAmount);

            tge.updateMilestone();

            uint8 newMilestone = tge.currentPLSMilestone();
            PLSMilestone memory newPLSMilestone = tge.getPlsMilestones(newMilestone);
            uint256 excessPls = amount - amountOfPls;

            tge.updatePLSRaised(newMilestone, excessAmount, excessPls);
            tge.updateUserPLSdonations(newMilestone, msg.sender, excessAmount);

            uint256 userpegAllocationExcess = excessAmount * newPLSMilestone.priceOfPeg;
            tge.updateUserPLSpegAllocation(newMilestone, msg.sender, userpegAllocationExcess);
        } else if (
            plsMilestone.USDCOfPlsRaised + amountInUSDC > plsMilestone.USDCOfPlsTarget && currentMilestone == 10
        ) {
            uint256 excessAmount = (plsMilestone.USDCOfPlsRaised + amountInUSDC) - plsMilestone.USDCOfPlsTarget;
            uint256 amountToDonate = plsMilestone.USDCOfPlsTarget - plsMilestone.USDCOfPlsRaised;

            tge.updatePLSRaised(currentMilestone, amountToDonate, amount);
            tge.updateUserPLSdonations(currentMilestone, msg.sender, amountToDonate);

            uint256 userpegAllocationAmount = amountToDonate * plsMilestone.priceOfPeg; //get current milestone price
            tge.updateUserPLSpegAllocation(currentMilestone, msg.sender, userpegAllocationAmount);

            tge.updateMilestone();
            require(plsToken.transfer(msg.sender, excessAmount), "refund failed");
        } else {
            tge.updatePLSRaised(currentMilestone, amountInUSDC, amount);
            tge.updateUserPLSdonations(currentMilestone, msg.sender, amountInUSDC);

            ///@dev calculate userpegAllocation for user Per milestone.
            uint256 userpegAllocation = (amountInUSDC * plsMilestone.priceOfPeg * 1e18) / 1e12; //get current milestone price
            tge.updateUserPLSpegAllocation(currentMilestone, msg.sender, userpegAllocation);

            //check milestone
            tge.updateMilestone();
        }
        emit PLSDonated(msg.sender, amount, currentMilestone);
    }

    ///@notice for tests
    function randomPLSPrice() public view returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(block.prevrandao))) % 600000) + 900000;
    }

    function withdraw() external override {
        uint256 userBalance = plsBalance[msg.sender];
        require(userBalance != 0, "insuffient balance");
        plsBalance[msg.sender] = 0;
        require(plsToken.transfer(msg.sender, userBalance), "withdrawal failed");
    }
}

