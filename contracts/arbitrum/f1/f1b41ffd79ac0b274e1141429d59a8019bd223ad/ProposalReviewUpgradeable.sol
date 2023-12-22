// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

contract ProposalReviewUpgradeable is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    struct Proposal {
        uint id;
        address submitter;
        uint8 proposalType;
        string description;
        uint depositAmount;
    }

    IERC20 public rh2O;

    bool public isEmergency;

    mapping(uint => bool) public resolvedProposals;

    event ProposalConfirmed(Proposal proposal);
    event ProposalDeclined(Proposal proposal);

    event EmergencyModeSet(bool isEmergency);

    event ProposalResolved(uint id);

    function initialize(address _rh2O) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        rh2O = IERC20(_rh2O);
    }

    modifier notEmergency() {
        require(!isEmergency, "Emergency");
        _;
    }

    function confirmProposal(
        Proposal calldata proposal
    ) external nonReentrant onlyOwner notEmergency {
        require(proposal.proposalType != 0, "Proposal type unknown");
        require(
            proposal.submitter != address(0),
            "Proposal submitter is not set"
        );

        if (proposal.depositAmount > 0) {
            rh2O.safeTransfer(_msgSender(), proposal.depositAmount);
        }

        emit ProposalConfirmed(proposal);
    }

    function declineProposal(
        Proposal calldata proposal
    ) external nonReentrant onlyOwner notEmergency {
        require(proposal.proposalType != 0, "Proposal type unknown");
        require(
            proposal.submitter != address(0),
            "Proposal submitter is not set"
        );

        uint depositAmount = proposal.depositAmount;

        if (proposal.depositAmount > 0) {
            rh2O.safeTransfer(proposal.submitter, depositAmount);
        }

        emit ProposalDeclined(proposal);
    }

    function resolveProposal(
        uint id
    ) external nonReentrant onlyOwner notEmergency {
        require(!resolvedProposals[id], "Proposal is resolved");

        resolvedProposals[id] = true;

        emit ProposalResolved(id);
    }

    function resolveProposalWithTransfer(
        uint id,
        address[] calldata tokens,
        uint[] calldata amounts,
        address[] calldata receivers
    ) external nonReentrant onlyOwner notEmergency {
        require(!resolvedProposals[id], "Proposal is resolved");
        require(
            tokens.length == amounts.length &&
                amounts.length == receivers.length,
            "Invalid params"
        );

        for (uint i; i < tokens.length; i++) {
            IERC20 tokenContract = IERC20(tokens[i]);
            require(
                tokenContract.balanceOf(address(this)) >= amounts[i],
                "Can't transfer token"
            );

            tokenContract.safeTransfer(receivers[i], amounts[i]);
        }

        resolvedProposals[id] = true;

        emit ProposalResolved(id);
    }

    function setEmergency(bool _isEmergency) external onlyOwner {
        isEmergency = _isEmergency;

        emit EmergencyModeSet(isEmergency);
    }

    function emergencyWithdraw(
        address token,
        address to,
        uint amount
    ) external onlyOwner {
        require(isEmergency, "Not allowed");

        IERC20(token).safeTransfer(to, amount);
    }

    function setRH2O(address _rh2O) external onlyOwner {
        rh2O = IERC20(_rh2O);
    }
}

