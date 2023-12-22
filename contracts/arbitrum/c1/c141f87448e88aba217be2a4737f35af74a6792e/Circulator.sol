// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./Pausable.sol";
import "./ECDSA.sol";
import "./ICircleBridge.sol";
import "./FeeOperator.sol";

/// @author chadxeth
/// @title IBurnLimit
/// @dev This interface is used to check burn limits from CCTP's local minter.
interface IBurnLimit {
    /// @notice Fetches the burn limit for a specific address.
    /// @param _address The address for which to fetch the burn limit.
    /// @return Returns the burn limit for the provided address.
    function burnLimitsPerMessage(address _address) external view returns (uint256);
}

contract Circulator is FeeOperator, Pausable {
    using SafeERC20 for IERC20; // Library for safe ERC20 operations.
    using ECDSA for bytes32; // Library for ECDSA signature operations.

    ICircleBridge public circleBridge; /// Reference to the Circle Bridge contract/interface.
    IBurnLimit public localMinter; /// Reference to the local minter interface.

    uint8 public immutable sourceChain; /// Source chain ID.
    uint256 public delegateFee; /// Fee for delegators.
    uint256 public serviceFee; /// Service fee for operations.
    uint256 constant FEE_DENOMINATOR = 1e6; /// Denominator for fee calculations.

    mapping(uint32 => uint256) public relayerFeeMaps; /// Mapping of destination domain to relayer fee.
    mapping(uint32 => uint256) public baseFeeMaps; /// Mapping of destination domain to base fee.
    mapping(address => bool) public delegators; /// List of authorized delegators.

    /// @dev Struct for encapsulating data needed for deposit with permit.
    struct PermitDepositData {
        address sender;
        bytes32 recipient;
        uint32 destinationDomain;
        address burnToken;
        uint256 amount;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Emitted when a deposit is made.
    /// @param sender Address of the sender.
    /// @param receiver Address of the receiver.
    /// @param destinationDomain Destination domain ID.
    /// @param amount Amount deposited.
    /// @param fee Fee taken for this deposit.
    /// @param nonce Unique nonce for this deposit.
    /// @param burnToken Token that was burned.
    event Deposited(
        address indexed sender,
        bytes32 indexed receiver,
        uint32 indexed destinationDomain,
        uint256 amount,
        uint256 fee,
        uint64 nonce,
        address burnToken
    );

    /// @notice Emitted when a deposit is made with a permit.
    /// @param relayer Address of the relayer.
    /// @param sender Address of the sender.
    /// @param receiver Address of the receiver.
    /// @param destinationDomain Destination domain ID.
    /// @param amount Amount deposited.
    /// @param fee Fee taken for this deposit with permit.
    /// @param nonce Unique nonce for this deposit with permit.
    /// @param burnToken Token that was burned.
    event PermitDeposited(
        address indexed relayer,
        address indexed sender,
        bytes32 receiver,
        uint32 indexed destinationDomain,
        uint256 amount,
        uint256 fee,
        uint64 nonce,
        address burnToken
    );

    /// @notice Emitted when the relayer fee for a destination is updated.
    /// @param destinationDomain Destination domain ID.
    /// @param fee New relayer fee.
    event DestinationRelayerFeeUpdated(uint32 indexed destinationDomain, uint256 fee);

    /// @notice Emitted when the base fee for a destination is updated.
    /// @param destinationDomain Destination domain ID.
    /// @param fee New base fee.
    event DestinationBaseFeeUpdated(uint32 indexed destinationDomain, uint256 fee);

    /// @notice Emitted when the delegate fee is updated.
    /// @param fee New delegate fee.
    event DelegateFeeUpdated(uint256 fee);

    /// @notice Emitted when a delegator's status is updated.
    /// @param delegator Address of the delegator.
    event DelegatorUpdated(address indexed delegator);

    /**
     * @notice Initializes the contract with provided parameters.
     * @dev Constructor to set up initial configurations of the bridge contract.
     * @param _circleBridge Address of the CircleBridge contract.
     * @param _localMinter Address of the local minter contract.
     * @param _feeCollector Address of the fee collector.
     * @param _delegators List of initial delegator addresses to be set.
     * @param _sourceChain ID of the source chain.
     * @param _delegateFee Fixed fee for the source chain.
     * @param _serviceFeePercentage Percentage of the service fee (for the source chain).
     * @param _domainIds List of domain IDs.
     * @param _relayerFeeMaps List of relayer fees corresponding to each domain ID.
     * @param _baseFeeMaps List of base fees corresponding to each domain ID.
     */
    constructor(
        address _circleBridge,
        address _localMinter,
        address _feeCollector,
        address[] memory _delegators,
        uint8 _sourceChain,
        uint256 _delegateFee,
        uint256 _serviceFeePercentage,
        uint32[] memory _domainIds,
        uint256[] memory _relayerFeeMaps,
        uint256[] memory _baseFeeMaps
    ) FeeOperator(_feeCollector) {
        // Set circle bridge address
        circleBridge = ICircleBridge(_circleBridge);
        // Set local minter address
        localMinter = IBurnLimit(_localMinter);
        // Set approved delegators
        for (uint256 i = 0; i < _delegators.length; i++) {
            delegators[_delegators[i]] = true;
        }
        // Set base fee and relayer fees
        for (uint256 i = 0; i < _domainIds.length; i++) {
            relayerFeeMaps[_domainIds[i]] = _relayerFeeMaps[i];
            baseFeeMaps[_domainIds[i]] = _baseFeeMaps[i];
        }
        // Source chain fixed fee
        delegateFee = _delegateFee;
        // Service fee (Always source chain) is a %
        serviceFee = _serviceFeePercentage;
        // Set source chain domain id
        sourceChain = _sourceChain;
    }

    /**
     * @notice Modifier to ensure that a given burn amount for a token doesn't exceed the allowed burn limit.
     * @dev Queries the `burnLimitsPerMessage` from the `localMinter` to get the maximum allowed burn amount for the token.
     * @param token The address of the token to be burnt.
     * @param amount The amount of the token being requested to burn.
     */
    modifier onlyWithinBurnLimit(address token, uint256 amount) {
        uint256 _allowedBurnAmount = localMinter.burnLimitsPerMessage(token);
        require(_allowedBurnAmount > 0, 'Burn token not supported');
        require(amount <= _allowedBurnAmount, 'Burn amount exceeds per tx limit');
        _;
    }

    /**
     * @notice Deposits a specified amount to the bridge and emits a `Deposited` event.
     * @dev This function burns a token amount for the given recipient and destination domain.
     * @param _amount Amount to be deposited.
     * @param _recipient The address of the recipient in bytes32 format.
     * @param _destinationDomain The ID of the destination domain.
     * @param _burnToken The token to be transferred and deposited.
     * @return _nonce A unique identifier for this deposit.
     */
    function deposit(
        uint256 _amount,
        bytes32 _recipient,
        uint32 _destinationDomain,
        address _burnToken
    ) external whenNotPaused onlyWithinBurnLimit(_burnToken, _amount) returns (uint64 _nonce) {
        // Calculate regular deposit fee
        uint256 fee = totalFee(_amount, _destinationDomain);
        // Check if fee is covered
        require(_amount > fee, 'fee not covered');
        // Transfer tokens to be burned to this contract
        IERC20(_burnToken).safeTransferFrom(msg.sender, address(this), _amount);
        // Deposit tokens to the bridge
        _nonce = circleBridge.depositForBurn(_amount - fee, _destinationDomain, _recipient, _burnToken);
        // Emit an event
        emit Deposited(msg.sender, _recipient, _destinationDomain, _amount, fee, _nonce, _burnToken);
    }

    /**
     * @notice Deposits on behalf of a user using a permit (off-chain signature).
     * @dev Only a registered delegator can call this function to deposit on behalf of a user.
     * @param data Struct containing deposit details including sender, recipient, amount, domain, and permit signature.
     */
    function permitDeposit(
        PermitDepositData calldata data
    ) external whenNotPaused onlyWithinBurnLimit(data.burnToken, data.amount) {
        // Check if the delegator is authorized
        require(delegators[msg.sender], 'not delegator');
        // Calculate delegate mode deposit fee
        uint256 fee = totalFee(data.amount, data.destinationDomain) + delegateFee;
        // Check if fee is covered
        require(data.amount > fee, 'amount too small');
        // Get amount to be bridged
        uint256 bridgeAmt = data.amount - fee;

        // Permit
        IERC20Permit(data.burnToken).permit(
            data.sender,
            address(this),
            data.amount,
            data.deadline,
            data.v,
            data.r,
            data.s
        );

        // Transfer tokens to be burned to this contract
        IERC20(data.burnToken).safeTransferFrom(data.sender, address(this), data.amount);
        // Deposit tokens to the bridge
        uint64 _nonce = circleBridge.depositForBurn(bridgeAmt, data.destinationDomain, data.recipient, data.burnToken);

        // Emit an event
        emit PermitDeposited(
            msg.sender, // The relayer address
            data.sender, // The user address that signed the permit
            data.recipient, // The recipient address
            data.destinationDomain, // The destination domain ID
            bridgeAmt, // The amount bridged
            fee, // The fee taken for Circulator
            _nonce, // The nonce for this deposit
            data.burnToken // The token that was burned
        );
    }

    /**
     * @notice Calculates the total fee for a given amount and destination domain.
     * @dev The function computes the service fee for the provided amount and adds the relayer fee
     * associated with the specified destination domain. The total fee is the greater of the sum
     * or the base fee associated with the destination domain.
     * @param _amount Amount for which the fee needs to be calculated.
     * @param _destinationDomain The domain ID for which relayer and base fees are fetched.
     * @return _finalFee The total fee to be applied.
     */
    function totalFee(uint256 _amount, uint32 _destinationDomain) public view returns (uint256 _finalFee) {
        uint256 _txFee = getServiceFee(_amount) + relayerFeeMaps[_destinationDomain];
        _finalFee = _max(_txFee, baseFeeMaps[_destinationDomain]);
    }

    /**
     * @notice Calculates the service fee for a given amount.
     * @dev This function computes the service fee by multiplying the provided amount with the service fee percentage
     * and dividing by the fee denominator.
     * @param _amount Amount for which the service fee needs to be calculated.
     * @return _fee Calculated service fee for the provided amount.
     */
    function getServiceFee(uint256 _amount) public view returns (uint256 _fee) {
        _fee = (_amount * serviceFee) / FEE_DENOMINATOR;
    }

    /**
     * @notice Sets the relayer fee for a specific destination domain.
     * @dev Only callable by the contract owner.
     * @param _destinationDomain The domain ID for which the relayer fee is set.
     * @param _fee The new relayer fee to be set.
     */
    function setDestinationRelayerFee(uint32 _destinationDomain, uint256 _fee) external onlyOwner {
        relayerFeeMaps[_destinationDomain] = _fee;
        emit DestinationRelayerFeeUpdated(_destinationDomain, _fee);
    }

    /**
     * @notice Sets the base fee for a specific destination domain.
     * @dev Only callable by the contract owner.
     * @param _destinationDomain The domain ID for which the base fee is set.
     * @param _fee The new base fee to be set.
     */
    function setDestinationBaseFee(uint32 _destinationDomain, uint256 _fee) external onlyOwner {
        baseFeeMaps[_destinationDomain] = _fee;
        emit DestinationBaseFeeUpdated(_destinationDomain, _fee);
    }

    /**
     * @notice Updates the delegate fee amount.
     * @dev Only callable by the contract owner.
     * @param _newFee The new delegate fee to be set.
     */
    function setDelegateFee(uint256 _newFee) external onlyOwner {
        delegateFee = _newFee;
        emit DelegateFeeUpdated(_newFee);
    }

    /**
     * @notice Updates the service fee percentage.
     * @dev Only callable by the contract owner.
     * @param _newFeePercentage The new service fee percentage to be set.
     */
    function setServiceFee(uint256 _newFeePercentage) external onlyOwner {
        serviceFee = _newFeePercentage;
    }

    /**
     * @notice Set the status for multiple delegators at once.
     * @dev Only callable by the contract owner. Emits a `DelegatorUpdated` event for each updated delegator.
     * @param _delegators An array of delegator addresses to update.
     * @param _status The new status (true or false) to be set for the given delegators.
     */
    function setDelegators(address[] memory _delegators, bool _status) external onlyOwner {
        for (uint256 i = 0; i < _delegators.length; i++) {
            delegators[_delegators[i]] = _status;
            emit DelegatorUpdated(_delegators[i]);
        }
    }

    /**
     * @notice Approve the CircleBridge to spend a specified amount of a token on behalf of this contract.
     * @dev Only callable by the contract owner.
     * @param _token The address of the token to approve.
     * @param _allowance The amount of tokens to approve for spending by the CircleBridge.
     */
    function circleBridgeApprove(address _token, uint256 _allowance) external onlyOwner {
        IERC20(_token).safeApprove(address(circleBridge), _allowance);
    }

    /**
     * @notice Pauses all functionality of the contract.
     * @dev Only callable by the contract owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resumes all paused functionalities of the contract.
     * @dev Only callable by the contract owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Returns the maximum of two given numbers.
     * @param a First number.
     * @param b Second number.
     * @return The maximum of the two numbers.
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /**
     * @notice Fallback function to receive Ether.
     * @dev This function allows the contract to receive Ether. It is intentionally left empty.
     */
    receive() external payable {}
}

