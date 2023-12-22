// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Address} from "./Address.sol";
import {EnumerableSet} from "./EnumerableSet.sol";
import {IERC1155} from "./IERC1155.sol";
import {IERC1271} from "./IERC1271.sol";
import {IERC165} from "./interfaces_IERC165.sol";
import {IERC20, SafeERC20} from "./SafeERC20.sol";
import {IERC2981} from "./IERC2981.sol";
import {IERC721} from "./IERC721.sol";
import {Ownable} from "./Ownable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

import {IWETH} from "./IWETH.sol";
import {IOwnable} from "./IOwnable.sol";
import {IStrategy} from "./IStrategy.sol";
import {ITransferManager} from "./ITransferManager.sol";
import {Orders} from "./Orders.sol";

contract Exchange is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ERC721 interfaceID
    bytes4 public constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    // ERC1155 interfaceID
    bytes4 public constant INTERFACE_ID_ERC1155 = 0xd9b67a26;
    // ERC2981 interfaceID
    bytes4 public constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    bytes32 public immutable DOMAIN_SEPARATOR;
    address public protocolFeeRecipient;

    EnumerableSet.AddressSet private strategies;
    EnumerableSet.AddressSet private currencies;
    mapping(address => address) public transferManagers;
    mapping(address => address) private royaltiesSetters;
    mapping(address => address) private royaltiesRecipients;
    mapping(address => uint256) private royaltiesFees;
    mapping(address => uint256) public userMinOrderNonce;
    mapping(address => mapping(uint256 => bool)) private userOrderNonceUsed;

    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event CurrencyAdded(address indexed currency);
    event CurrencyRemoved(address indexed currency);
    event TransferManagerSet(address indexed collection, address indexed manager);
    event RoyaltyUpdated(address indexed collection, address indexed setter, address indexed recipient, uint fee);
    event NewProtocolFeeRecipient(address indexed protocolFeeRecipient);
    event CancelAllOrders(address indexed user, uint256 newMinNonce);
    event CancelMultipleOrders(address indexed user, uint256[] orderNonces);

    event RoyaltyPayment(
        address indexed collection,
        uint256 indexed tokenId,
        address indexed royaltyRecipient,
        address currency,
        uint256 amount
    );

    event TakerAsk(
        bytes32 orderHash, // bid hash of the maker order
        uint256 orderNonce, // user order nonce
        address indexed taker, // sender address for the taker ask order
        address indexed maker, // maker address of the initial bid order
        address indexed strategy, // strategy that defines the execution
        address currency, // currency address
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount, // amount of tokens transferred
        uint256 price // final transacted price
    );

    event TakerBid(
        bytes32 orderHash, // ask hash of the maker order
        uint256 orderNonce, // user order nonce
        address indexed taker, // sender address for the taker bid order
        address indexed maker, // maker address of the initial ask order
        address indexed strategy, // strategy that defines the execution
        address currency, // currency address
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount, // amount of tokens transferred
        uint256 price // final transacted price
    );


    constructor() {
        // Calculate the domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0xdcf7dbdbbd58eefcb557d348dd887c6c7064e80212c9036fba1f54798f889fec, // keccak256("NilExchange")
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1")) for versionId = 1
                block.chainid,
                address(this)
            )
        );
    }

    function isStrategy(address strategy) external view returns (bool) {
        return strategies.contains(strategy);
    }

    function viewStrategiesCount() external view returns (uint256) {
        return strategies.length();
    }

    function viewStrategies(uint256 cursor, uint256 size) external view returns (address[] memory, uint256) {
        uint256 length = size;
        if (length > strategies.length() - cursor) {
            length = strategies.length() - cursor;
        }
        address[] memory addresses = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            addresses[i] = strategies.at(cursor + i);
        }
        return (addresses, cursor + length);
    }

    function isCurrency(address currency) external view returns (bool) {
        return currencies.contains(currency);
    }

    function viewCurrenciesCount() external view returns (uint256) {
        return currencies.length();
    }

    function viewCurrencies(uint256 cursor, uint256 size) external view returns (address[] memory, uint256) {
        uint256 length = size;
        if (length > currencies.length() - cursor) {
            length = currencies.length() - cursor;
        }
        address[] memory addresses = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            addresses[i] = currencies.at(cursor + i);
        }
        return (addresses, cursor + length);
    }

    function viewUserOrderNonceUsed(address user, uint256 orderNonce) external view returns (bool) {
        return userOrderNonceUsed[user][orderNonce];
    }

    function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
        emit NewProtocolFeeRecipient(_protocolFeeRecipient);
    }

    function addStrategy(address strategy) external onlyOwner {
        require(!strategies.contains(strategy), "Already present");
        strategies.add(strategy);
        emit StrategyAdded(strategy);
    }

    function removeStrategy(address strategy) external onlyOwner {
        require(strategies.contains(strategy), "Not present");
        strategies.remove(strategy);
        emit StrategyRemoved(strategy);
    }

    function addCurrency(address currency) external onlyOwner {
        require(!currencies.contains(currency), "Already present");
        currencies.add(currency);
        emit CurrencyAdded(currency);
    }

    function removeCurrency(address currency) external onlyOwner {
        require(currencies.contains(currency), "Not present");
        currencies.remove(currency);
        emit CurrencyRemoved(currency);
    }

    function setTransferManager(address collection, address manager) external onlyOwner {
        transferManagers[collection] = manager;
        emit TransferManagerSet(collection, manager);
    }

    function updateRoyalty(address collection, address setter, address recipient, uint fee) external {
      address collectionSetter;
      try IOwnable(collection).owner() returns (address setter) {
          collectionSetter = setter;
      } catch {
          try IOwnable(collection).admin() returns (address setter) {
              collectionSetter = setter;
          } catch {}
      }
      require(msg.sender == owner() || msg.sender == royaltiesSetters[collection] || msg.sender == collectionSetter);
      require(!IERC165(collection).supportsInterface(INTERFACE_ID_ERC2981), "Must not be ERC2981");
      require(
          (IERC165(collection).supportsInterface(INTERFACE_ID_ERC721) ||
              IERC165(collection).supportsInterface(INTERFACE_ID_ERC1155)),
          "Not ERC721/ERC1155"
      );
      royaltiesSetters[collection] = setter;
      royaltiesRecipients[collection] = recipient;
      royaltiesFees[collection] = fee;
      emit RoyaltyUpdated(collection, setter, recipient, fee);
    }

    function cancelAllOrdersForSender(uint256 minNonce) external {
        require(minNonce > userMinOrderNonce[msg.sender], "Cancel: Order nonce lower than current");
        require(minNonce < userMinOrderNonce[msg.sender] + 500000, "Cancel: Cannot cancel more orders");
        userMinOrderNonce[msg.sender] = minNonce;

        emit CancelAllOrders(msg.sender, minNonce);
    }

    function cancelMultipleMakerOrders(uint256[] calldata orderNonces) external {
        require(orderNonces.length > 0, "Cancel: Cannot be empty");

        for (uint256 i = 0; i < orderNonces.length; i++) {
            require(orderNonces[i] >= userMinOrderNonce[msg.sender], "Cancel: Order nonce lower than current");
            userOrderNonceUsed[msg.sender][orderNonces[i]] = true;
        }

        emit CancelMultipleOrders(msg.sender, orderNonces);
    }

    function matchAskWithTakerBid(Orders.TakerOrder calldata takerBid, Orders.MakerOrder calldata makerAsk)
        external
        nonReentrant
    {
        require((makerAsk.isOrderAsk) && (!takerBid.isOrderAsk), "Order: Wrong sides");
        require(msg.sender == takerBid.taker, "Order: Taker must be the sender");

        // Check the maker ask order
        bytes32 askHash = hashMakerOrder(makerAsk);
        _validateOrder(makerAsk, askHash);

        (bool isExecutionValid, uint256 tokenId, uint256 amount) = IStrategy(makerAsk.strategy)
            .canExecuteTakerBid(takerBid, makerAsk);

        require(isExecutionValid, "Strategy: Execution invalid");

        // Update maker ask order status to true (prevents replay)
        userOrderNonceUsed[makerAsk.signer][makerAsk.nonce] = true;

        // Execution part 1/2
        _transferFeesAndFunds(
            makerAsk.strategy,
            makerAsk.collection,
            tokenId,
            makerAsk.currency,
            msg.sender,
            makerAsk.signer,
            takerBid.price,
            makerAsk.minPercentageToAsk
        );

        // Execution part 2/2
        _transferNonFungibleToken(makerAsk.collection, makerAsk.signer, takerBid.taker, tokenId, amount);

        emit TakerBid(
            askHash,
            makerAsk.nonce,
            takerBid.taker,
            makerAsk.signer,
            makerAsk.strategy,
            makerAsk.currency,
            makerAsk.collection,
            tokenId,
            amount,
            takerBid.price
        );
    }

    function matchBidWithTakerAsk(Orders.TakerOrder calldata takerAsk, Orders.MakerOrder calldata makerBid)
        external
        nonReentrant
    {
        require((!makerBid.isOrderAsk) && (takerAsk.isOrderAsk), "Order: Wrong sides");
        require(msg.sender == takerAsk.taker, "Order: Taker must be the sender");

        // Check the maker bid order
        bytes32 bidHash = hashMakerOrder(makerBid);
        _validateOrder(makerBid, bidHash);

        (bool isExecutionValid, uint256 tokenId, uint256 amount) = IStrategy(makerBid.strategy)
            .canExecuteTakerAsk(takerAsk, makerBid);
        require(isExecutionValid, "Strategy: Execution invalid");

        // Update maker bid order status to true (prevents replay)
        userOrderNonceUsed[makerBid.signer][makerBid.nonce] = true;

        // Execution part 1/2
        _transferNonFungibleToken(makerBid.collection, msg.sender, makerBid.signer, tokenId, amount);

        // Execution part 2/2
        _transferFeesAndFunds(
            makerBid.strategy,
            makerBid.collection,
            tokenId,
            makerBid.currency,
            makerBid.signer,
            takerAsk.taker,
            takerAsk.price,
            takerAsk.minPercentageToAsk
        );

        emit TakerAsk(
            bidHash,
            makerBid.nonce,
            takerAsk.taker,
            makerBid.signer,
            makerBid.strategy,
            makerBid.currency,
            makerBid.collection,
            tokenId,
            amount,
            takerAsk.price
        );
    }

    function _transferFeesAndFunds(
        address strategy,
        address collection,
        uint256 tokenId,
        address currency,
        address from,
        address to,
        uint256 amount,
        uint256 minPercentageToAsk
    ) internal {
        // Initialize the final amount that is transferred to seller
        uint256 finalSellerAmount = amount;

        // 1. Protocol fee
        {
            uint256 protocolFeeAmount = (amount * IStrategy(strategy).fee()) / 10000;

            // Check if the protocol fee is different than 0 for this strategy
            if ((protocolFeeRecipient != address(0)) && (protocolFeeAmount != 0)) {
                IERC20(currency).safeTransferFrom(from, protocolFeeRecipient, protocolFeeAmount);
                finalSellerAmount -= protocolFeeAmount;
            }
        }

        // 2. Royalty fee
        {
            (address royaltyFeeRecipient, uint256 royaltyFeeAmount) = _royaltyFeeAndRecipient(collection, tokenId, amount);

            // Check if there is a royalty fee and that it is different to 0
            if ((royaltyFeeRecipient != address(0)) && (royaltyFeeAmount != 0)) {
                IERC20(currency).safeTransferFrom(from, royaltyFeeRecipient, royaltyFeeAmount);
                finalSellerAmount -= royaltyFeeAmount;

                emit RoyaltyPayment(collection, tokenId, royaltyFeeRecipient, currency, royaltyFeeAmount);
            }
        }

        require((finalSellerAmount * 10000) >= (minPercentageToAsk * amount), "Fees: Higher than expected");

        // 3. Transfer final amount (post-fees) to seller
        {
            IERC20(currency).safeTransferFrom(from, to, finalSellerAmount);
        }
    }

    function _transferNonFungibleToken(
        address collection,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        address transferManager = transferManagers[collection];
        if (transferManager == address(0)) {
            if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC721)) {
                IERC721(collection).safeTransferFrom(from, to, tokenId);
                return;
            } else if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC1155)) {
                IERC1155(collection).safeTransferFrom(from, to, tokenId, amount, "");
                return;
            }
        }
        require(transferManager != address(0), "No transfer manager for collection");
        ITransferManager(transferManager).transferNFT(collection, from, to, tokenId, amount);
    }

    function _validateOrder(Orders.MakerOrder calldata makerOrder, bytes32 orderHash) internal view {
        require(makerOrder.signer != address(0), "Invalid order signer");
        require(makerOrder.amount > 0, "Invalid order amount: 0");
        require(currencies.contains(makerOrder.currency), "Invalid currency");
        require(strategies.contains(makerOrder.strategy), "Invalid strategy");
        require(
            (!userOrderNonceUsed[makerOrder.signer][makerOrder.nonce]) &&
                (makerOrder.nonce >= userMinOrderNonce[makerOrder.signer]),
            "Matching order expired"
        );
        require(
            _verify(
                orderHash,
                makerOrder.signer,
                makerOrder.v,
                makerOrder.r,
                makerOrder.s,
                DOMAIN_SEPARATOR
            ),
            "Invalid signature"
        );
    }

    function _royaltyFeeAndRecipient(
        address collection,
        uint256 tokenId,
        uint256 amount
    ) public view returns (address, uint256) {
        address recipient = royaltiesRecipients[collection];
        uint royaltyAmount = amount * royaltiesFees[collection] / 10000;
        if ((recipient == address(0)) || (royaltyAmount == 0)) {
            if (IERC165(collection).supportsInterface(INTERFACE_ID_ERC2981)) {
                (recipient, royaltyAmount) = IERC2981(collection).royaltyInfo(tokenId, amount);
            }
        }
        return (recipient, royaltyAmount);
    }

    function hashMakerOrder(Orders.MakerOrder memory makerOrder) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                Orders.MAKER_ORDER_HASH,
                makerOrder.isOrderAsk,
                makerOrder.signer,
                makerOrder.collection,
                makerOrder.price,
                makerOrder.tokenId,
                makerOrder.amount,
                makerOrder.strategy,
                makerOrder.currency,
                makerOrder.nonce,
                makerOrder.startTime,
                makerOrder.endTime,
                makerOrder.minPercentageToAsk,
                keccak256(makerOrder.params)
            )
        );
    }

    function _verify(
        bytes32 hash,
        address signer,
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 domainSeparator
    ) internal view returns (bool) {
        // \x19\x01 is the standardized encoding prefix
        // https://eips.ethereum.org/EIPS/eip-712#specification
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, hash));
        if (Address.isContract(signer)) {
            // 0x1626ba7e is the interfaceId for signature contracts (see IERC1271)
            return IERC1271(signer).isValidSignature(digest, abi.encodePacked(r, s, v)) == 0x1626ba7e;
        } else {
            return _recover(digest, v, r, s) == signer;
        }
    }

    function _recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        // https://ethereum.stackexchange.com/questions/83174/is-it-best-practice-to-check-signature-malleability-in-ecrecover
        // https://crypto.iacr.org/2019/affevents/wac/medias/Heninger-BiasedNonceSense.pdf
        require(
            uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0,
            "Signature: Invalid s parameter"
        );

        require(v == 27 || v == 28, "Signature: Invalid v parameter");

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "Signature: Invalid signer");

        return signer;
    }
}

