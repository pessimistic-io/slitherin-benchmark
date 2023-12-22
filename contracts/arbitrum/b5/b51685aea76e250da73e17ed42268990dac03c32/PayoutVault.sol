// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";

error Unauthorized();
error BadRequest();
error BadAddress();
error BadPayment();
error OverAttributed();
error IncorrectAmount();
error ImproperCampaignState();
error PaymentTypeDoesNotExist();

/// @title PayoutVault
/// @author spindl.xyz
/// @notice This is implementation contract for proxies that is used to update campaign funds & proivde ability to fund/withdraw for campaign managers and recipients
contract PayoutVault is Initializable, OwnableUpgradeable {
    address public managerAddress;
    address public workerAddress;
    mapping(address => bool) public paymentTypes;
    mapping(uint32 => Campaign) public campaigns;

    /// @notice we use this for ids & increment. Can also be tracked total # of campaigns / recipients created
    uint32 public campaignCounter;

    struct Campaign {
        uint256 totalBudget;
        CampaignStatus status;
        address paymentType;
        uint256 totalEarned;
        mapping(address => RecipientDetails) recipients;
    }

    enum CampaignStatus {
        NONE,
        CREATED,
        ACTIVE,
        PAUSED,
        COMPLETED
    }

    struct RecipientDetails {
        RecipientStatus status;
        uint256 earned;
        uint256 withdrawn;
    }

    struct RecipientUpdates {
        address addr;
        uint256 earned;
    }

    struct RecipientEarnings {
        uint32 campaignId;
        uint256 amount;
    }

    /// @dev this struct is used to update both campaigns and recipients
    struct UpdateDetails {
        uint32 campaignId;
        RecipientUpdates[] recipients;
    }

    enum RecipientStatus {
        NONE,
        ACTIVE,
        PAUSED
    }

    enum RecipientWithdrawType {
        PUSH,
        PULL
    }

    /// @notice used to initialize contract in place of constructor for security reasons
    function initialize(
        address _owner,
        address _managerAddress,
        address _workerAddress,
        address[] calldata _paymentTypes
    ) public initializer {
        __Ownable_init();

        /// @dev transfering ownership to multisig owner upon init
        _transferOwnership(_owner);

        /// @dev add initial data
        managerAddress = _managerAddress;
        workerAddress = _workerAddress;

        /// @dev this will be used for native currency such as Eth or Matic
        paymentTypes[address(0)] = true;

        /// @dev we don't expect to have more than 5-10 payment options
        for (uint16 i; i < _paymentTypes.length; i++) {
            paymentTypes[_paymentTypes[i]] = true;
        }
    }

    /// @notice Events
    event ManagerAddressUpdated(address indexed oldAddress, address newAddress);
    event WorkerAddressUpdated(address indexed oldAddress, address newAddress);
    event CampaignCreated(uint32 indexed campaignId, address paymentType);
    event RecipientAdded(uint32 indexed campaignId, address recipientAddress);
    event RecipientStatusUpdated(uint32 indexed campaignId, address indexed addr, RecipientStatus status);
    event CampaignFunded(uint32 indexed campaignId, uint256 updatedBudget);
    event UpdateCompleted(
        uint32 indexed campaignId,
        address indexed recipientAddress,
        address paymentType,
        uint256 newEarnings
    );
    event CampaignStatusUpdated(uint32 indexed campaignId, CampaignStatus oldState, CampaignStatus newState);

    /// @dev totalWithdrawn is accumulation of total withdrawn by recipient up until this point
    event WithdrawSuccess(
        uint32 indexed campaignId,
        address indexed recipientAddress,
        address paymentType,
        uint256 totalWithdrawn,
        RecipientWithdrawType withdrawType
    );
    event PaymentAdded(address paymentAddress);
    event BalanceWithdrawn(uint32 campaignId, uint256 withdrawAmount, uint256 newTotalBalance);

    /// @notice Modifiers

    modifier onlyOwnerAndWorker() {
        if (msg.sender != owner() && msg.sender != workerAddress) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyInProgressCampaigns(uint32 _campaignId) {
        CampaignStatus campaignStatus = campaigns[_campaignId].status;
        if (campaignStatus == CampaignStatus.ACTIVE || campaignStatus == CampaignStatus.CREATED) {
            _;
        } else {
            revert ImproperCampaignState();
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice in case worker address needs to be updated
    /// @param _newAddress new worker address
    function setWorkerAddress(address _newAddress) external virtual onlyOwner {
        if (_newAddress == workerAddress) {
            revert BadAddress();
        }
        /// @dev allowing owner to set address(0) in case we want to not allow any worker address to update
        emit WorkerAddressUpdated(workerAddress, _newAddress);
        workerAddress = _newAddress;
    }

    /// @notice in case manager address needs to be updated
    /// @param _newAddress new manager address
    function setManagerAddress(address _newAddress) external virtual onlyOwner {
        if (_newAddress == address(0) || _newAddress == managerAddress) {
            revert BadAddress();
        }
        emit ManagerAddressUpdated(managerAddress, _newAddress);

        managerAddress = _newAddress;
    }

    /// @notice create campaign
    /// @param _paymentType payment type for campaign
    /// @param _recipientAddresses array of recipient addresses
    function createCampaign(
        address _paymentType,
        address[] memory _recipientAddresses
    ) external virtual onlyOwnerAndWorker {
        if (!paymentTypes[_paymentType]) {
            revert PaymentTypeDoesNotExist();
        }

        /// @dev using campaignCounter to increment & create campaignId
        uint32 campaignId = campaignCounter + 1;

        /// @dev address(0) is used for native currency such as Eth or Matic
        campaigns[campaignId].paymentType = _paymentType;

        /// @dev default values
        campaigns[campaignId].status = CampaignStatus.CREATED;

        campaignCounter = campaignId;

        emit CampaignCreated(campaignId, _paymentType);

        /// @dev add recipients
        if (_recipientAddresses.length > 0) {
            addRecipients(campaignId, _recipientAddresses);
        }
    }

    /// @notice fund campaign with either erc20 or native currency. if native, we will receive via `msg.value`. if erc20, we use `_amount`
    /// @param _campaignId campaign id
    /// @param _amount amount of erc20 token to fund campaign with
    function fundCampaign(
        uint32 _campaignId,
        uint256 _amount
    ) external payable virtual onlyInProgressCampaigns(_campaignId) {
        if (msg.sender != managerAddress && msg.sender != owner()) {
            revert Unauthorized();
        }

        address paymentType = campaigns[_campaignId].paymentType;
        bool isNativeToken = bool(paymentType == address(0));

        /// @dev address(0) is the native crypto like Eth, Matic, etc.
        if (isNativeToken) {
            // msg.value is the amount of native currency sent with the transaction. should be > 0
            if (msg.value == 0 || _amount > 0) {
                revert BadPayment();
            }

            /// @dev this allows manager to add to budget multiple times
            campaigns[_campaignId].totalBudget += msg.value;
        } else {
            // _amount is the amount of EC20 token sent with the transaction. should be > 0
            if (_amount == 0 || msg.value > 0) {
                revert BadPayment();
            }

            uint256 balanceBefore = IERC20(paymentType).balanceOf(address(this));
            bool success = IERC20(paymentType).transferFrom(msg.sender, address(this), _amount);
            require(success, "ERC20_TRANSFER_FAILED");
            uint256 balanceAfter = IERC20(paymentType).balanceOf(address(this));

            /// @dev we are calculating totalBudget with before/after balance in case we deal with fee on transfer ERC20 tokens
            campaigns[_campaignId].totalBudget += (balanceAfter - balanceBefore);
        }

        emit CampaignFunded(_campaignId, campaigns[_campaignId].totalBudget);
    }

    /// @notice add recipients to campaign
    /// @param _campaignId campaign id
    /// @param _recipientAddresses array of recipient addresses
    function addRecipients(
        uint32 _campaignId,
        address[] memory _recipientAddresses
    ) public virtual onlyOwnerAndWorker onlyInProgressCampaigns(_campaignId) {
        if (_recipientAddresses.length == 0) {
            revert BadAddress();
        }

        for (uint32 i; i < _recipientAddresses.length; i++) {
            address _address = _recipientAddresses[i];
            RecipientDetails storage recipient = campaigns[_campaignId].recipients[_address];

            if (_address == address(0) || _address == managerAddress || !(recipient.status == RecipientStatus.NONE)) {
                revert BadAddress();
            }
            recipient.status = RecipientStatus.ACTIVE;
            emit RecipientAdded(_campaignId, _address);
        }
    }

    /// @notice get recipient details
    /// @param _campaignId campaign id
    /// @param _recipientAddress recipient address
    /// @return recipient details
    function getRecipient(uint32 _campaignId, address _recipientAddress) public view returns (RecipientDetails memory) {
        return campaigns[_campaignId].recipients[_recipientAddress];
    }

    function withdrawManyRecipientEarnings(RecipientEarnings[] memory _campaigns, address _to) external virtual {
        for (uint32 i; i < _campaigns.length; ) {
            withdrawRecipientEarnings(_campaigns[i].campaignId, _campaigns[i].amount, _to);

            /// @dev for gas saving since front-end should not be sending a massive array for this method
            unchecked {
                i++;
            }
        }
    }

    /// @notice withdraw recipient available earnings
    /// @param _campaignId campaign id
    /// @param _amount amount to withdraw
    /// @param _to address to send funds to
    function withdrawRecipientEarnings(uint32 _campaignId, uint256 _amount, address _to) public virtual {
        address paymentType = campaigns[_campaignId].paymentType;

        RecipientDetails storage recipient = campaigns[_campaignId].recipients[msg.sender];
        if (!(recipient.status == RecipientStatus.ACTIVE) || _amount == 0) {
            revert BadRequest();
        }

        /// @dev can only withdraw if campaign is active/completed
        if (
            campaigns[_campaignId].status == CampaignStatus.PAUSED ||
            campaigns[_campaignId].status == CampaignStatus.CREATED
        ) {
            revert Unauthorized();
        }

        uint256 recipientAvailableBalance = recipient.earned - recipient.withdrawn;

        /// @dev cannot withdraw more than difference between earned & already withdrawn
        /// @dev also, in `peformUpkeep` we ensure totalEarned cannot exceed totalBalance so we don't have to worry about withdrawing more than total balance in a campaign here
        if (_amount > recipientAvailableBalance) {
            revert IncorrectAmount();
        }
        // update state before sending money
        recipient.withdrawn += _amount;

        /// @dev address(0) is the native crypto like Eth, Matic, etc.
        if (paymentType == address(0)) {
            (bool success, ) = address(_to).call{ value: _amount }("");
            require(success, "TRANSFER_FAILED");

            /// @dev this is for ERC20 payment types
        } else {
            bool success = IERC20(paymentType).transfer(address(_to), _amount);
            require(success, "TRANSFER_FAILED");
        }

        emit WithdrawSuccess(_campaignId, msg.sender, paymentType, recipient.withdrawn, RecipientWithdrawType.PULL);
    }

    /// @notice push withdraw recipient(s) available earnings
    /// @param _campaignId campaign id
    /// @param _recipientAddresses array of recipient addresses
    /// @dev this is for batch push withdraws
    function pushRecipientEarnings(
        uint32 _campaignId,
        address[] memory _recipientAddresses
    ) external virtual onlyOwnerAndWorker {
        /// @dev can only withdraw if campaign is active/completed
        if (
            campaigns[_campaignId].status == CampaignStatus.PAUSED ||
            campaigns[_campaignId].status == CampaignStatus.CREATED
        ) {
            revert Unauthorized();
        }

        address paymentType = campaigns[_campaignId].paymentType;
        for (uint32 i; i < _recipientAddresses.length; i++) {
            address recipientAddress = _recipientAddresses[i];
            RecipientDetails storage recipient = campaigns[_campaignId].recipients[recipientAddress];
            uint256 amount = recipient.earned - recipient.withdrawn;

            /// @dev if amount is 0, don't waste gas trying to transfer funds
            if (amount == 0) {
                continue;
            }

            // update state before sending money
            recipient.withdrawn += amount;

            /// @dev address(0) is the native crypto like Eth, Matic, etc.
            if (paymentType == address(0)) {
                (bool success, ) = address(recipientAddress).call{ value: amount }("");
                require(success, "TRANSFER_FAILED");

                /// @dev this is for ERC20 payment types
            } else {
                bool success = IERC20(paymentType).transfer(address(recipientAddress), amount);
                require(success, "TRANSFER_FAILED");
            }
            emit WithdrawSuccess(
                _campaignId,
                recipientAddress,
                paymentType,
                recipient.withdrawn,
                RecipientWithdrawType.PUSH
            );
        }
    }

    /// @notice set recipient status
    /// @param _campaignId campaign id
    /// @param _recipientAddress recipient address
    /// @param _status recipient status
    function setRecipientStatus(
        uint32 _campaignId,
        address _recipientAddress,
        RecipientStatus _status
    ) external virtual onlyOwnerAndWorker {
        RecipientDetails memory recipient = getRecipient(_campaignId, _recipientAddress);

        if (
            recipient.status == _status || recipient.status == RecipientStatus.NONE || _status == RecipientStatus.NONE
        ) {
            revert BadRequest();
        }

        campaigns[_campaignId].recipients[_recipientAddress].status = _status;
        emit RecipientStatusUpdated(_campaignId, _recipientAddress, _status);
    }

    /// @notice this to update both campaigns and recipients
    /// @param performData encoded data for updating campaigns and recipients
    function updateBalances(bytes calldata performData) external virtual onlyOwnerAndWorker {
        UpdateDetails[] memory updateArray = abi.decode(performData, (UpdateDetails[]));

        /// @dev updates should not have large arrays & should updates should be broken down into smaller chunks if needed
        for (uint32 i = 0; i < updateArray.length; ) {
            UpdateDetails memory updateObj = updateArray[i];

            Campaign storage campaign = campaigns[updateObj.campaignId];

            /// @dev storing as local variable to save gas
            uint256 _campaignTotalEarned = campaign.totalEarned;

            if (campaign.status == CampaignStatus.NONE || campaign.status == CampaignStatus.CREATED) {
                revert ImproperCampaignState();
            }

            RecipientUpdates[] memory recipients = updateObj.recipients;

            for (uint32 k = 0; k < recipients.length; ) {
                RecipientUpdates memory recipientUpdate = recipients[k];
                RecipientDetails storage recipient = campaigns[updateObj.campaignId].recipients[recipientUpdate.addr];

                /// @dev if recipient does not exist, implicitly create it
                if (recipient.status == RecipientStatus.NONE) {
                    recipient.status = RecipientStatus.ACTIVE;
                    emit RecipientAdded(updateObj.campaignId, recipientUpdate.addr);
                }

                /// @dev you cannot make earned less than already withdrawn
                if (recipient.withdrawn > recipientUpdate.earned) {
                    revert IncorrectAmount();
                }

                /// @dev we are adding the difference to totalEarned. it should never be negative.
                _campaignTotalEarned = _campaignTotalEarned - recipient.earned + recipientUpdate.earned;

                /// @dev for update recipient
                recipient.earned = recipientUpdate.earned;

                unchecked {
                    k++;
                }

                emit UpdateCompleted(
                    updateObj.campaignId,
                    recipientUpdate.addr,
                    campaign.paymentType,
                    recipient.earned
                );
            }

            /// @dev preventing over-attribution of earnings on the campaign level
            if (_campaignTotalEarned > campaign.totalBudget) {
                revert OverAttributed();
            }

            campaign.totalEarned = _campaignTotalEarned;

            /// @dev for gas saving since we know that there is no way array will be bigger than uint32
            unchecked {
                i++;
            }
        }
    }

    /// @notice set campaign status
    /// @param _campaignId campaign id
    /// @param _status campaign status
    function setCampaignStatus(uint32 _campaignId, CampaignStatus _status) external virtual onlyOwnerAndWorker {
        CampaignStatus currentStatus = campaigns[_campaignId].status;

        /// @dev campaign status cannot be set to NONE or CREATED.
        /// Campaign is set to status CREATED once via `createCampaign` function
        if (
            currentStatus == CampaignStatus.NONE ||
            currentStatus == _status || /// @dev campaign status cannot be set to same status
            _status == CampaignStatus.CREATED || /// @dev campaign status cannot be set to CREATED
            _status == CampaignStatus.NONE /// @dev campaign status cannot be set to NONE
        ) {
            revert BadRequest();
        }
        emit CampaignStatusUpdated(_campaignId, currentStatus, _status);

        campaigns[_campaignId].status = _status;
    }

    /// @notice add new erc20 payment type to be used by campaign mananger
    /// @param _address erc20 token address
    function addERC20Payment(address _address) external virtual onlyOwnerAndWorker {
        /// @dev payment type already exists
        if (paymentTypes[_address] == true) {
            revert BadRequest();
        }
        paymentTypes[_address] = true;
        emit PaymentAdded(_address);
    }

    /// @notice withdraw remaing balance from campaign if not spent
    /// @dev if campaign status is COMPLETED, campaign manager can withdraw the remaining balance that wasn't spent
    /// @param _campaignId campaign id
    /// @param _to address to send the remaining balance
    function withdrawRemainingCampaignBalance(uint32 _campaignId, address _to) external virtual {
        if (msg.sender != managerAddress) {
            revert Unauthorized();
        }

        uint256 totalEarned = campaigns[_campaignId].totalEarned;
        Campaign storage campaign = campaigns[_campaignId];

        if (campaign.status != CampaignStatus.COMPLETED || totalEarned == campaign.totalBudget) {
            revert BadRequest();
        }

        uint256 withdrawAmount = campaign.totalBudget - totalEarned;
        /// @dev update state before transferring funds
        /// @dev we want to make campaign manager cannot withdraw the same remainder twice
        campaign.totalBudget = totalEarned;

        /// @dev address(0) is the native crypto like Eth, Matic, etc.
        if (campaign.paymentType == address(0)) {
            (bool success, ) = address(_to).call{ value: withdrawAmount }("");
            require(success, "TRANSFER_FAILED");

            /// @dev this is for ERC20 payment types
        } else {
            bool success = IERC20(campaign.paymentType).transfer(address(_to), withdrawAmount);
            require(success, "TRANSFER_FAILED");
        }

        /// @dev emit event. this is the new total budget after we withdrew
        emit BalanceWithdrawn(_campaignId, withdrawAmount, campaign.totalBudget);
    }
}

