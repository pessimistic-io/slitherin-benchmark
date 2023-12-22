//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import {IAccessControlHolder, IAccessControl} from "./IAccessControlHolder.sol";
import {IPaymentReceiver} from "./IPaymentReceiver.sol";
import {ZeroAddressGuard} from "./ZeroAddressGuard.sol";
import {ZeroAmountGuard} from "./ZeroAmountGuard.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {ECDSA} from "./ECDSA.sol";
import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";

contract PaymentReceiver is
    IAccessControlHolder,
    IPaymentReceiver,
    ZeroAddressGuard,
    ZeroAmountGuard
{
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    bytes32 public constant GEMS_TRADER_ROLE = keccak256("GEMS_TRADER_ROLE");

    string constant BUY_TYPE =
        "buyGems(address wallet, uint256 tokenId, uint256 amount, uint256 price, uint256 deadline)";

    address public immutable override treasury;
    IERC721 public immutable override collection;
    IAccessControl public immutable override acl;
    IERC20 public immutable override paymentToken;

    modifier deadlineIsNotMissed(uint256 deadline) {
        if (block.timestamp > deadline) {
            revert AfterDeadline();
        }
        _;
    }

    constructor(
        IAccessControl acl_,
        IERC20 paymentToken_,
        IERC721 collection_,
        address treasury_
    ) {
        acl = acl_;
        collection = collection_;
        paymentToken = paymentToken_;
        treasury = treasury_;
    }

    function buyGems(
        address wallet,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 deadline,
        bytes calldata signature
    )
        external
        override
        notZeroAddress(wallet)
        notZeroAmount(amount)
        notZeroAmount(price)
        deadlineIsNotMissed(deadline)
    {
        if (collection.ownerOf(tokenId) == address(0)) {
            revert TokenNotExists();
        }

        bytes32 hash = buyGemsHash(wallet, tokenId, amount, price, deadline);
        address signer = hash.toEthSignedMessageHash().recover(signature);
        _esnureHasGemsTraderRole(signer);
        paymentToken.safeTransferFrom(msg.sender, treasury, price);

        emit GemsPurchased(
            wallet,
            collection,
            tokenId,
            msg.sender,
            amount,
            price
        );
    }

    function buyGemsHash(
        address wallet,
        uint256 tokenId,
        uint256 amount,
        uint256 price,
        uint256 deadline
    ) public view override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    uint16(0x1901),
                    _domainSeperator(),
                    keccak256(
                        abi.encode(
                            BUY_TYPE,
                            wallet,
                            tokenId,
                            amount,
                            price,
                            deadline
                        )
                    )
                )
            );
    }

    function _esnureHasGemsTraderRole(address wallet) internal view {
        if (!acl.hasRole(GEMS_TRADER_ROLE, wallet)) {
            revert NotAllowedToExchangeGems(wallet);
        }
    }

    function _domainSeperator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,uint256 signedAt)"
                    ),
                    keccak256(bytes("Sparta")),
                    keccak256(bytes("1")),
                    _chainId(),
                    address(this),
                    keccak256(bytes("Sparta"))
                )
            );
    }

    function _chainId() internal view returns (uint256 chainId_) {
        assembly {
            chainId_ := chainid()
        }
    }
}

