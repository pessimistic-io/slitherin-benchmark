// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Pausable.sol";
import "./AccessControl.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./IAssetForwarder.sol";
import "./IWETH.sol";
import "./ITokenMessenger.sol";
import "./IMessageHandler.sol";

contract AssetForwarder is
    AccessControl,
    ReentrancyGuard,
    Pausable,
    IAssetForwarder
{
    using SafeERC20 for IERC20;

    string public chainId;
    IWETH public immutable wrappedNativeToken;
    bytes32 public routerMiddlewareBase;
    address public gatewayContract;
    // address of USDC
    address public usdc;
    // USDC token messenger
    ITokenMessenger public tokenMessenger;

    uint256 public depositNonce;
    mapping(bytes32 => DestDetails) destDetails;
    uint256 public constant MAX_TRANSFER_SIZE = 1e36;
    bytes32 public constant RESOURCE_SETTER = keccak256("RESOURCE_SETTER");
    bytes32 public constant PAUSER = keccak256("PAUSER");
    mapping(bytes32 => bool) public executeRecord;
    uint256 public MIN_GAS_THRESHHOLD;
    uint256 public pauseStakeAmountMin;
    uint256 public pauseStakeAmountMax;
    uint256 public totalStakedAmount;
    bool public isCommunityPauseEnabled = true;

    address private constant ZERO_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address private constant ETH_ADDRESS =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event CommunityPaused(address indexed pauser, uint256 stakedAmount);

    error MessageAlreadyExecuted();
    error InvalidGateway();
    error InvalidRequestSender();
    error InvalidRefundData();
    error InvalidAmount();
    error AmountTooLarge();
    error MessageExcecutionFailedWithLowGas();
    error InvalidFee();

    constructor(
        address _wrappedNativeTokenAddress,
        address _gatewayContract,
        address _usdcAddress,
        address _tokenMessenger,
        bytes memory _routerMiddlewareBase,
        string memory _chainId,
        uint _minGasThreshhold
    ) {
        chainId = _chainId;
        wrappedNativeToken = IWETH(_wrappedNativeTokenAddress);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        gatewayContract = _gatewayContract;
        usdc = _usdcAddress;
        routerMiddlewareBase = keccak256(_routerMiddlewareBase);
        MIN_GAS_THRESHHOLD = _minGasThreshhold;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RESOURCE_SETTER, msg.sender);
        _grantRole(PAUSER, msg.sender);
    }

    function update(
        uint index,
        address _gatewayContract,
        bytes calldata _routerMiddlewareBase,
        uint256 minPauseStakeAmount,
        uint256 maxPauseStakeAmount
    ) public onlyRole(RESOURCE_SETTER) {
        if (index == 1) {
            gatewayContract = _gatewayContract;
        } else if (index == 2) {
            routerMiddlewareBase = keccak256(_routerMiddlewareBase);
        } else if (index == 3) {
            pauseStakeAmountMin = minPauseStakeAmount;
            pauseStakeAmountMax = maxPauseStakeAmount;
        }
    }

    function updateChainId(
        string memory _newChainId
    ) public onlyRole(RESOURCE_SETTER) {
        chainId = _newChainId;
    }

    /// @notice Function used to set usdc token messenger address
    /// @notice Only RESOURCE_SETTER can call this function
    /// @param  _tokenMessenger address of token messenger
    function updateTokenMessenger(
        address _tokenMessenger
    ) external onlyRole(RESOURCE_SETTER) {
        tokenMessenger = ITokenMessenger(_tokenMessenger);
    }

    function pause() external onlyRole(PAUSER) whenNotPaused {
        _pause();
    }

    /// @notice Unpauses deposits on the handler.
    /// @notice Only callable by an address that currently has the PAUSER role.
    function unpause() external onlyRole(PAUSER) whenPaused {
        _unpause();
    }

    function getChainId() internal view returns (uint256 id) {
        assembly {
            id := chainid()
        }
    }

    function isNative(address token) internal pure returns (bool) {
        return (token == ZERO_ADDRESS || token == ETH_ADDRESS);
    }

    function setDestDetails(
        bytes32[] memory _destChainIdBytes,
        DestDetails[] memory _destDetails
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _destChainIdBytes.length == _destDetails.length,
            "invalid length"
        );
        for (uint256 idx = 0; idx < _destDetails.length; idx++) {
            destDetails[_destChainIdBytes[idx]] = _destDetails[idx];
        }
    }

    function iDepositUSDC(
        uint256 partnerId,
        bytes32 destChainIdBytes,
        bytes32 recipient,
        uint256 amount
    ) external payable nonReentrant whenNotPaused {
        require(
            destDetails[destChainIdBytes].isSet && usdc != address(0),
            "usdc not supported either on src on dst chain"
        );
        if (msg.value != destDetails[destChainIdBytes].fee) revert InvalidFee();
        if (amount > MAX_TRANSFER_SIZE) revert AmountTooLarge();

        IERC20(usdc).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(usdc).safeApprove(address(tokenMessenger), amount);

        uint64 nonce = tokenMessenger.depositForBurn(
            amount,
            destDetails[destChainIdBytes].domainId,
            recipient,
            usdc
        ); // it will emit event DepositForBurn, returns nonce

        emit iUSDCDeposited(
            partnerId,
            amount,
            destChainIdBytes,
            ++depositNonce,
            nonce,
            usdc,
            recipient,
            msg.sender
        );
    }

    function iDeposit(
        uint256 partnerId,
        bytes32 destChainIdBytes,
        bytes calldata recipient,
        address srcToken,
        uint256 amount,
        uint256 destAmount
    ) external payable nonReentrant whenNotPaused {
        if (amount > MAX_TRANSFER_SIZE) revert AmountTooLarge();

        if (isNative(srcToken)) {
            if (amount != msg.value) revert InvalidAmount();
            wrappedNativeToken.deposit{value: msg.value}(); // only amount should be deposited
            srcToken = address(wrappedNativeToken);
        } else {
            IERC20(srcToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        emit FundsDeposited(
            partnerId,
            amount,
            destChainIdBytes,
            destAmount,
            ++depositNonce,
            srcToken,
            recipient,
            msg.sender
        );
    }

    function iDepositInfoUpdate(
        address srcToken,
        uint256 feeAmount,
        uint256 depositId,
        bool initiatewithdrawal
    ) external payable nonReentrant whenNotPaused {
        if (initiatewithdrawal) {
            assert(msg.value == 0);
            emit DepositInfoUpdate(
                srcToken,
                0,
                depositId,
                ++depositNonce,
                initiatewithdrawal,
                msg.sender
            );
            return;
        }
        if (isNative(srcToken)) {
            if (feeAmount != msg.value) revert InvalidAmount();
            wrappedNativeToken.deposit{value: msg.value}(); // only amount should be deposited
            srcToken = address(wrappedNativeToken);
        } else {
            IERC20(srcToken).safeTransferFrom(
                msg.sender,
                address(this),
                feeAmount
            );
        }
        emit DepositInfoUpdate(
            srcToken,
            feeAmount,
            depositId,
            ++depositNonce,
            initiatewithdrawal,
            msg.sender
        );
    }

    function iDepositMessage(
        uint256 partnerId,
        bytes32 destChainIdBytes,
        bytes calldata recipient,
        address srcToken,
        uint256 amount,
        uint256 destAmount,
        bytes memory message
    ) external payable nonReentrant whenNotPaused {
        if (amount > MAX_TRANSFER_SIZE) revert AmountTooLarge();

        if (isNative(srcToken)) {
            if (amount != msg.value) revert InvalidAmount();
            wrappedNativeToken.deposit{value: msg.value}(); // only amount should be deposited
            srcToken = address(wrappedNativeToken);
        } else {
            IERC20(srcToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }
        emit FundsDepositedWithMessage(
            partnerId,
            amount,
            destChainIdBytes,
            destAmount,
            ++depositNonce,
            srcToken,
            recipient,
            msg.sender,
            message
        );
    }

    function iRelay(
        RelayData memory relayData,
        string memory forwarderRouterAddress
    ) external payable nonReentrant whenNotPaused {
        // Check is message is already executed
        bool isNativeToken = isNative(relayData.destToken);
        if (isNativeToken) {
            relayData.destToken = address(wrappedNativeToken);
        }
        bytes32 messageHash = keccak256(
            abi.encode(
                relayData.amount,
                relayData.srcChainId,
                relayData.depositId,
                relayData.destToken,
                relayData.recipient,
                relayData.depositor,
                address(this)
            )
        );
        if (executeRecord[messageHash]) revert MessageAlreadyExecuted();
        executeRecord[messageHash] = true;

        if (relayData.destToken == address(wrappedNativeToken)) {
            if (relayData.amount != msg.value) revert InvalidAmount();

            //slither-disable-next-line arbitrary-send-eth
            payable(relayData.recipient).transfer(relayData.amount);
        } else {
            IERC20(relayData.destToken).safeTransferFrom(
                msg.sender,
                relayData.recipient,
                relayData.amount
            );
        }

        emit FundsPaid(
            messageHash,
            msg.sender,
            ++depositNonce,
            forwarderRouterAddress
        );
    }

    function iRelayMessage(
        RelayDataMessage memory relayData,
        string memory forwarderRouterAddress
    ) external payable nonReentrant whenNotPaused {
        bool isNativeToken = isNative(relayData.destToken);
        if (isNativeToken) {
            relayData.destToken = address(wrappedNativeToken);
        }
        // Check is message is already executed
        bytes32 messageHash = keccak256(
            abi.encode(
                relayData.amount,
                relayData.srcChainId,
                relayData.depositId,
                relayData.destToken,
                relayData.recipient,
                relayData.depositor,
                address(this),
                relayData.message
            )
        );
        if (executeRecord[messageHash]) revert MessageAlreadyExecuted();
        executeRecord[messageHash] = true;

        IERC20(relayData.destToken).safeTransferFrom(
            msg.sender,
            relayData.recipient,
            relayData.amount
        );
        bytes memory execData;
        bool execFlag;
        if (isContract(relayData.recipient) && relayData.message.length > 0) {
            (execFlag, execData) = relayData.recipient.call(
                abi.encodeWithSelector(
                    IMessageHandler.handleMessage.selector,
                    relayData.destToken,
                    relayData.amount,
                    relayData.message
                )
            );
            if (!execFlag && gasleft() < MIN_GAS_THRESHHOLD)
                revert MessageExcecutionFailedWithLowGas();
        }
        emit FundsPaidWithMessage(
            messageHash,
            msg.sender,
            ++depositNonce,
            forwarderRouterAddress,
            execFlag,
            execData
        );
    }

    function iReceive(
        string calldata requestSender,
        bytes memory packet,
        string calldata
    ) external returns (bytes memory) {
        if (msg.sender != address(gatewayContract)) revert InvalidGateway();
        if (routerMiddlewareBase != keccak256(bytes(requestSender)))
            revert InvalidRequestSender();

        (
            address recipient,
            address[] memory tokens,
            uint256[] memory amounts
        ) = abi.decode(packet, (address, address[], uint256[]));
        uint256 count = tokens.length;

        if (count != amounts.length) revert InvalidRefundData();

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);
        }
        return "";
    }

    function bytesToAddress(
        bytes memory bys
    ) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 20))
        }
    }

    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    // TODO: do we need this? We should not have it like this as this will
    // not be decentralized. We should have withdraw fees instead.
    function rescue(
        address token
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        IERC20(token).safeTransfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    function toggleCommunityPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        isCommunityPauseEnabled = !isCommunityPauseEnabled;
    }

    function communityPause() external payable whenNotPaused {
        // Check if msg.value is within the allowed range
        require(isCommunityPauseEnabled, "Community pause is disabled");
        require(
            pauseStakeAmountMin != 0 && pauseStakeAmountMax != 0,
            "Set Stake Amount Range"
        );
        require(
            msg.value >= pauseStakeAmountMin &&
                msg.value <= pauseStakeAmountMax,
            "Stake amount out of range"
        );
        uint256 newTotalStakedAmount = totalStakedAmount + msg.value;
        totalStakedAmount = newTotalStakedAmount;

        _pause();

        emit CommunityPaused(msg.sender, msg.value);
    }

    function withdrawStakeAmount() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            address(this).balance >= totalStakedAmount,
            "Insufficient funds"
        );
        uint256 withdrawalAmount = totalStakedAmount;
        totalStakedAmount = 0;
        payable(msg.sender).transfer(withdrawalAmount);
    }
}

