// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {ISocketMarketplace} from "./ISocketMarketPlace.sol";
import {Ownable} from "./Ownable.sol";
import {RescueFundsLib} from "./RescueFundsLib.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import "./ECDSA.sol";

contract Solver is Ownable {
    using SafeTransferLib for ERC20;
    // -------------------------------------------------- ERRORS AND VARIABLES -------------------------------------------------- //

    error SignerMismatch();
    error InvalidNonce();
    error SocketExtractorFailed();

    // nonce usage data
    mapping(address => mapping(uint256 => bool)) public nonceUsed;

    /// @notice _signer address of the signer
    address signerAddress;

    /// @notice SOCKET_EXTRACTOR address of the socket extractor contract
    address public immutable SOCKET_EXTRACTOR;

    // -------------------------------------------------- CONSTRUCTOR -------------------------------------------------- //

    /**
     * @notice Constructor.
     * @param _socketExtractor address of socket market place.
     * @param _owner address of the contract owner
     * @param _signer address of the signer
     */
    constructor(
        address _socketExtractor,
        address _owner,
        address _signer
    ) Ownable(_owner) {
        SOCKET_EXTRACTOR = _socketExtractor;
        signerAddress = _signer;
    }

    // -------------------------------------------------- CALL SOCKET EXTRACTOR FUNCTION -------------------------------------------------- //

    function callExtractor(
        uint256 nonce,
        uint256 value,
        bytes calldata signature,
        bytes calldata extractorData
    ) external {
        // recovering signer.
        address recoveredSigner = ECDSA.recover(
            keccak256(
                abi.encodePacked(
                    "\x19Ethereum Signed Message:\n32",
                    keccak256(
                        abi.encode(
                            address(this),
                            nonce,
                            block.chainid, // uint256
                            value,
                            extractorData
                        )
                    )
                )
            ),
            signature
        );

        if (signerAddress != recoveredSigner) revert SignerMismatch();
        // nonce is used by gated roles and we don't expect nonce to reach the max value of uint256
        if (nonceUsed[signerAddress][nonce]) revert InvalidNonce();

        // Mark nonce for that address as used.
        nonceUsed[signerAddress][nonce] = true;

        (bool success, ) = SOCKET_EXTRACTOR.call{value: value}(extractorData);

        if (!success) revert SocketExtractorFailed();
    }

    // -------------------------------------------------- ADMIN FUNCTION -------------------------------------------------- //

    /**
     * @notice Rescues funds from the contract if they are locked by mistake.
     * @param token_ The address of the token contract.
     * @param rescueTo_ The address where rescued tokens need to be sent.
     * @param amount_ The amount of tokens to be rescued.
     */
    function rescueFunds(
        address token_,
        address rescueTo_,
        uint256 amount_
    ) external onlyOwner {
        RescueFundsLib.rescueFunds(token_, rescueTo_, amount_);
    }

    /// @notice Sets the signer address if a new signer is needed.
    function setSignerAddress(address _signerAddress) external onlyOwner {
        signerAddress = _signerAddress;
    }

    /// @notice Approves the tokens against socket extractor.
    function setApprovalForExtractor(
        address[] memory tokenAddresses,
        bool isMax
    ) external onlyOwner {
        for (uint32 index = 0; index < tokenAddresses.length; ) {
            ERC20(tokenAddresses[index]).safeApprove(
                SOCKET_EXTRACTOR,
                isMax ? type(uint256).max : 0
            );
            unchecked {
                ++index;
            }
        }
    }
}

