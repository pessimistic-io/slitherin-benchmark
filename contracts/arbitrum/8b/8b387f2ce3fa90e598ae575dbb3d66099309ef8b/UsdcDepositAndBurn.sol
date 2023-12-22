// SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IUsdcDepositAndBurn.sol";
import "./SafeERC20Upgradeable.sol";
import "./UUPSUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ITokenMessenger.sol";

contract UsdcDepositAndBurn is Initializable, UUPSUpgradeable, AccessControlUpgradeable, IUsdcDepositAndBurn {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    address public usdc;
    address public erc20Handler;

    mapping(uint8 => DestDetails) public chainIdToDestDetails;
    ITokenMessenger public tokenMessenger;
    address public reserve;
    bytes32 public constant RESOURCE_SETTER = keccak256("RESOURCE_SETTER");

    event UsdcBurn(
        uint256 amount,
        uint8 destChainId,
        uint32 usdcDomainId,
        address mintRecipient,
        address usdc,
        address destCaller,
        uint256 nonce
    );

    function initialize(
        address _tokenMessenger,
        address _usdc,
        address _erc20Handler,
        address _reserve
    ) external initializer {
        __AccessControl_init();

        tokenMessenger = ITokenMessenger(_tokenMessenger);
        usdc = _usdc;
        erc20Handler = _erc20Handler;
        reserve = _reserve;

        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(RESOURCE_SETTER, msg.sender);
    }

    function setTokenMessenger(address _tokenMessenger) external onlyRole(RESOURCE_SETTER) {
        tokenMessenger = ITokenMessenger(_tokenMessenger);
    }

    function setUsdc(address _usdc) external onlyRole(RESOURCE_SETTER) {
        usdc = _usdc;
    }

    function setReserve(address _reserve) external onlyRole(RESOURCE_SETTER) {
        reserve = _reserve;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    function setDestDetails(DestDetails[] memory destDetails) external override onlyRole(RESOURCE_SETTER) {
        for (uint8 i = 0; i < destDetails.length; i++) {
            require(destDetails[i].chainId != 0, "Chain Id != 0");
            require(destDetails[i].reserveHandlerAddress != address(0), "Reserve handler != address(0)");
            require(destDetails[i].destCallerAddress != address(0), "Dest caller != address(0)");

            chainIdToDestDetails[destDetails[i].chainId] = DestDetails(
                destDetails[i].chainId,
                destDetails[i].usdcDomainId,
                destDetails[i].reserveHandlerAddress,
                destDetails[i].destCallerAddress
            );
        }
    }

    /// @notice Function to deposit and burn USDC on circle bridge contract
    /// @notice Only voyagerDepositHandler can call this function
    /// @param destChainId chainId of the dest chain
    /// @param amount Amount of USDC to be deposited and burnt
    function depositAndBurnUsdc(uint8 destChainId, uint256 amount) external override returns (uint64) {
        require(msg.sender == erc20Handler, "Only ERC20Handler");
        address _usdc = usdc;
        require(address(tokenMessenger) != address(0) && _usdc != address(0), "usdc or circle bridge not set");
        DestDetails memory destDetails = chainIdToDestDetails[destChainId];
        require(destDetails.reserveHandlerAddress != address(0), "dest chain not configured");
        ITokenMessenger _tokenMessenger = tokenMessenger;
        IERC20Upgradeable(_usdc).safeTransferFrom(reserve, address(this), amount);
        IERC20Upgradeable(_usdc).safeApprove(address(_tokenMessenger), amount);
        bytes32 _destCaller = bytes32(uint256(uint160(destDetails.destCallerAddress)));
        bytes32 _mintRecipient = bytes32(uint256(uint160(destDetails.reserveHandlerAddress)));
        uint64 usdcNonce = _tokenMessenger.depositForBurnWithCaller(
            amount,
            destDetails.usdcDomainId,
            _mintRecipient,
            _usdc,
            _destCaller
        );
        return usdcNonce;
    }

    /// @notice Function to change the destCaller and mintRecipient for a USDC burn tx.
    /// @notice Only DEFAULT_ADMIN can call this function.
    /// @param  originalMessage Original message received when the USDC was burnt.
    /// @param  originalAttestation Original attestation received from the API.
    /// @param  newDestCaller Address of the new destination caller.
    /// @param  newMintRecipient Address of the new mint recipient.
    function changeDestCallerOrMintRecipient(
        bytes memory originalMessage,
        bytes calldata originalAttestation,
        address newDestCaller,
        address newMintRecipient
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        bytes32 _destCaller = bytes32(uint256(uint160(newDestCaller)));
        bytes32 _mintRecipient = bytes32(uint256(uint160(newMintRecipient)));
        tokenMessenger.replaceDepositForBurn(originalMessage, originalAttestation, _destCaller, _mintRecipient);
    }
}

