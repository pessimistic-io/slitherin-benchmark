// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

import "./IERC20Metadata.sol";
import "./IDatabase.sol";

/// @title   Developer Wallet
/// @notice  Contract that a developer is deployed upon minting of Proof of Developer NFT
/// @author  Hyacinth
contract DeveloperWallet {
    /// EVENTS ///

    /// @notice             Emitted after bounty has been added to
    /// @param token        Address of token added to bounty
    /// @param auditId      Audit id of audit bounty is being added to
    /// @param amountAdded  Amount added to bounty
    event AddedToBounty(address indexed token, uint256 indexed auditId, uint256 indexed amountAdded);

    /// ERRORS ///

    /// @notice Error for if audit id is not being audited
    error NotBeingAudited();
    /// @notice Error for if msg.sender is not database
    error NotDatabase();
    /// @notice Error for if contrac was not developed by developer
    error NotDeveloper();
    /// @notice Error for if bounty has been paid out already
    error BountyPaid();
    /// @notice Error for if USDC balance too low
    error BalanceTooLow();

    /// STATE VARIABLES ///

    /// @notice Address of developer
    address public immutable owner;
    /// @notice Address of USDC
    address public immutable USDC;
    /// @notice Address of database contract
    address public immutable database;

    /// @notice Amount of tokens on bounties
    mapping(address => uint256) public tokenOnBounties;

    /// @notice Bounty amount of token on audit
    mapping(uint256 => mapping(address => uint256)) public bountyOnContract;

    /// @notice Token addresses on bounty
    mapping(uint256 => address[]) public tokenAddressOnBounty;

    /// @notice Bool if bounty has been paid out
    mapping(uint256 => bool) public bountyPaidOut;

    /// CONSTRUCTOR ///

    constructor(address owner_, address database_) {
        owner = owner_;
        database = database_;
        USDC = IDatabase(database_).USDC();
    }

    /// EXTERNAL FUNCTION ///

    /// @notice           Add to bounty of `auditId_`
    /// @param auditId_   Audit id to add bounty to
    /// @param amount_    Amount of stable to add to bounty
    /// @param transfer_  Bool if transferring token in or using what has been transferred directly
    /// @param token_     Address of token on bounty
    function addToBounty(uint256 auditId_, uint256 amount_, bool transfer_, address token_) external {
        (, address developer_, , , , ) = IDatabase(database).audits(auditId_);
        if ((developer_ != owner || developer_ != msg.sender) && database != msg.sender) revert NotDeveloper();
        (, , IDatabase.STATUS status_, , , ) = IDatabase(database).audits(auditId_);
        if (status_ != IDatabase.STATUS.PENDING) revert NotBeingAudited();
        if (transfer_) IERC20(token_).transferFrom(msg.sender, address(this), amount_);
        else {
            uint256 avail_ = IERC20(token_).balanceOf(address(this)) - tokenOnBounties[token_];
            if (avail_ < amount_) revert BalanceTooLow();
        }

        if (bountyOnContract[auditId_][token_] == 0) tokenAddressOnBounty[auditId_].push(token_);
        bountyOnContract[auditId_][token_] += amount_;
        tokenOnBounties[token_] += amount_;

        emit AddedToBounty(token_, auditId_, amount_);
    }

    /// DATABASE FUNCTION ///

    /// @notice                   Pays out bounty of `auditId_`
    /// @param auditId_           Id of audit to pay bounty out for
    /// @param collaborators_     Array of collaborators for `auditId_`
    /// @param percentsOfBounty_  Array of corresponding percents of bounty for `collaborators_`
    /// @return level_            Level of bounty
    function payOutBounty(
        uint256 auditId_,
        address[] calldata collaborators_,
        uint256[] calldata percentsOfBounty_
    ) external returns (uint256 level_) {
        if (msg.sender != database) revert NotDatabase();
        if (bountyPaidOut[auditId_]) revert BountyPaid();

        bountyPaidOut[auditId_] = true;

        (address auditor_, , , , , ) = IDatabase(database).audits(auditId_);

        (level_, ) = currentBountyLevel(auditId_);

        for (uint i; i < tokenAddressOnBounty[auditId_].length; ++i) {
            address token_ = tokenAddressOnBounty[auditId_][i];
            uint256 bounty_ = bountyOnContract[auditId_][token_];
            tokenOnBounties[token_] -= bounty_;
            bountyOnContract[auditId_][token_] = 0;
            uint256 bountyToDistribute_ = ((bounty_ * (100 - IDatabase(database).HYACINTH_FEE())) / 100);
            uint256 hyacinthReceives_ = bounty_ - bountyToDistribute_;
            IERC20(token_).transfer(IDatabase(database).hyacinthWallet(), hyacinthReceives_);

            uint256 collaboratorsReceived_;
            for (uint256 n; n < collaborators_.length; ++n) {
                uint256 collaboratorsReceives_ = (bountyToDistribute_ * percentsOfBounty_[n]) / 100;
                IERC20(token_).transfer(collaborators_[n], collaboratorsReceives_);
                collaboratorsReceived_ += collaboratorsReceives_;
            }

            uint256 auditorReceives_ = bountyToDistribute_ - collaboratorsReceived_;
            IERC20(token_).transfer(auditor_, auditorReceives_);
        }
    }

    /// @notice           Rolls over bounty of `previous_` to `new_`
    /// @param previous_  Audit id of roll overed audit
    /// @param new_       Audsit id of new audit after roll over
    function rollOverBounty(uint256 previous_, uint256 new_) external {
        if (msg.sender != database) revert NotDatabase();

        for (uint i; i < tokenAddressOnBounty[previous_].length; ++i) {
            address token_ = tokenAddressOnBounty[previous_][i];
            uint256 bounty_ = bountyOnContract[previous_][token_];

            bountyOnContract[previous_][token_] = 0;
            bountyOnContract[new_][token_] = bounty_;
        }

        tokenAddressOnBounty[new_] = tokenAddressOnBounty[previous_];
    }

    /// @notice           Function that allows developer to get a refund for bounty if no auditor or past deadline
    /// @param auditId_   Audit id to get refund for
    function refundBounty(uint256 auditId_) external {
        if (msg.sender != database) revert NotDatabase();
        for (uint i; i < tokenAddressOnBounty[auditId_].length; ++i) {
            address token_ = tokenAddressOnBounty[auditId_][i];
            uint256 bounty_ = bountyOnContract[auditId_][token_];
            bountyOnContract[auditId_][token_] = 0;
            tokenOnBounties[token_] -= bounty_;
            IERC20(token_).transfer(owner, bounty_);
        }
    }

    /// VIEW FUNCTIONS ///

    /// @notice          Returns current `level_` and `bounty_` of `auditId_`
    /// @param auditId_  Audit to check bounty for
    /// @return level_   Current level of `contract_` bounty
    /// @return bounty_  Current bouty of `contract_`
    function currentBountyLevel(uint256 auditId_) public view returns (uint256 level_, uint256 bounty_) {
        bounty_ = bountyOnContract[auditId_][USDC];

        uint256 decimals_ = 10 ** IERC20Metadata(USDC).decimals();
        if (bounty_ >= 1000 * decimals_) {
            if (bounty_ < 10000 * decimals_) level_ = 1;
            else if (bounty_ < 100000 * decimals_) level_ = 2;
            else level_ = 3;
        }
    }
}

