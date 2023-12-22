// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./EIP712Upgradeable.sol";
import "./ERC721Upgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./MathUpgradeable.sol";
import "./INft.sol";
import "./Buy.sol";
import "./BuyMany.sol";
import "./contextMixin.sol";

interface IProxyRegistry {
    function proxies(address) external view returns (address);
}

contract Nft is
    Initializable,
    ERC721Upgradeable,
    EIP712Upgradeable,
    OwnableUpgradeable,
    ContextMixin,
    INft
{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using AddressUpgradeable for address payable;
    using AddressUpgradeable for address;
    using StringsUpgradeable for uint256;
    using ECDSAUpgradeable for bytes32;
    CountersUpgradeable.Counter private _tokenIdCounter;
    Settings public settings;
    address payable public feeDestination;
    bool public makx;
    uint256 public feePercent;
    uint256 public collected;
    uint256 public adminWithdrawn;
    uint256 public feeWithdrawn;
    address public signitory;
    error MaxSupplyReached();
    error NotLive();
    error NftSaleAlreadyStarted();
    error SignatureIsExpired();
    error InvalidSignature();
    error LowAmount();
    error MakxBuilderIsEnabled();
    error MakxBuilderIsNotEnabled();
    error NoAmountIsAvailableToWithdraw();
    error ReferralsAreDisabled();
    // Base token URI
    string private baseURI;
    mapping(address => uint256) public refs;
    mapping(address => uint256) public refWithdrawals;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        NftInit calldata init,
        address payable _feeDestination,
        uint256 _feePercent
    ) public override initializer {
        __ERC721_init(init.name, init.symbol);
        __Ownable_init();
        __EIP712_init(init.name, "1");
        transferOwnership(init.owner);
        settings = Settings(
            init.feeTo,
            address(0),
            init.fee,
            init.refFee,
            init.supply,
            init.startTime,
            init.endTime
        );
        feeDestination = _feeDestination;
        feePercent = _feePercent;
        makx = init.makx != address(0);
        signitory = init.makx;
        baseURI = string(
            abi.encodePacked(
                "https://nft.makx.io/",
                StringsUpgradeable.toHexString(address(this))
            )
        );
    }

    modifier live() {
        isLive();
        _;
    }

    function isLive() internal {
        if (_tokenIdCounter.current() == settings.supply)
            revert MaxSupplyReached();
        if (
            block.timestamp < settings.startTime ||
            block.timestamp > settings.endTime
        ) revert NotLive();
        _tokenIdCounter.increment();
    }

    /**
     *  Owner can update settings
     * @param fee new fees to be charged
     * @param feeTo change fees destination address
     */
    function updateFees(
        uint256 fee,
        address payable feeTo
    ) external override onlyOwner {
        settings.fee = fee;
        settings.feeTo = feeTo;
    }

    /**
     * @param startTime change start time
     * @param endTime change start time
     */
    function updateSettings(
        uint256 startTime,
        uint256 endTime
    ) external override onlyOwner {
        if (block.timestamp > settings.startTime)
            revert NftSaleAlreadyStarted();
        settings.startTime = startTime;
        settings.endTime = endTime;
    }

    /**
     *
     * @param newURI Update the token baseURL
     */
    function setBaseURI(string calldata newURI) external onlyOwner {
        baseURI = string(
            abi.encodePacked(
                newURI,
                StringsUpgradeable.toHexString(address(this))
            )
        );
    }

    function setOpenseaRegistry(address openseaRegistry) external onlyOwner {
        settings.openseaRegistry = openseaRegistry;
    }

    function safeMint(
        address to,
        uint256 tokenId
    ) external override onlyOwner live {
        _safeMint(to, tokenId);
    }

    function buy(
        Buy.Info calldata req,
        bytes calldata signature,
        address ref
    ) external payable live {
        if (msg.value < req.amount) revert LowAmount();
        if (signitory != _hashTypedDataV4(Buy.dropHash(req)).recover(signature))
            revert InvalidSignature();
        _mint(req.to, req.tokenId);
        if (ref != address(0)) refs[ref] += req.amount;
        collected += req.amount;
    }

    function buyMany(
        BuyMany.Many calldata req,
        bytes calldata signature,
        address ref
    ) external payable live {
        if (msg.value < req.amount) revert LowAmount();
        if (
            signitory !=
            _hashTypedDataV4(BuyMany.buyHash(req)).recover(signature)
        ) revert InvalidSignature();
        for (uint8 i = 0; i < req.tokenIds.length; ) {
            _mint(req.to, req.tokenIds[i]);
            unchecked {
                i++;
            }
        }
        if (ref != address(0)) refs[ref] += req.amount;
        collected += req.amount;
    }

    function purchase(
        address to,
        uint256 tokenId,
        address ref
    ) external payable override live {
        if (makx) revert MakxBuilderIsEnabled();
        if (msg.value < settings.fee) revert LowAmount();
        _safeMint(to, tokenId);
        if (ref != address(0)) {
            refs[ref] += msg.value;
        }
        collected += msg.value;
    }

    function purchaseMany(
        address to,
        uint256[] calldata tokenIds,
        address ref
    ) external payable override live {
        if (makx) revert MakxBuilderIsEnabled();
        if (msg.value < (settings.fee * tokenIds.length)) revert LowAmount();
        for (uint8 i = 0; i < tokenIds.length; ) {
            _mint(to, tokenIds[i]);
            unchecked {
                i++;
            }
        }
        /**
         * check only first;
         */
        if (to.isContract())
            require(
                checkOnERC721Received(address(0), to, tokenIds[0], ""),
                "ERC721: transfer to non ERC721Receiver implementer"
            );
        if (ref != address(0)) {
            refs[ref] += msg.value;
        }
        collected += msg.value;
    }

    /** @dev Meta-transactions override for OpenSea. */
    function _msgSender() internal view override returns (address) {
        return ContextMixin.msgSender();
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        return
            string(abi.encodePacked(baseURI, "/", tokenId.toString(), ".json"));
    }

    /** @dev Contract-level metadata for OpenSea. */
    // Update for collection-specific metadata.
    function contractURI() external view returns (string memory) {
        return string(abi.encodePacked(baseURI, ".json"));
    }

    /**
     * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-free listings.
     */
    function isApprovedForAll(
        address _owner,
        address _operator
    ) public view override(ERC721Upgradeable) returns (bool isOperator) {
        // Whitelist OpenSea proxy contract for easy trading.
        if (settings.openseaRegistry != address(0)) {
            IProxyRegistry proxyRegistry = IProxyRegistry(
                settings.openseaRegistry
            );
            if (proxyRegistry.proxies(_owner) == _operator) {
                return true;
            }
        }
        return super.isApprovedForAll(_owner, _operator);
    }

    function withdraw() external {
        uint256 refPercent = settings.refFee;
        if (collected == 0) revert NoAmountIsAvailableToWithdraw();
        uint256 refFee = refPercent > 0
            ? MathUpgradeable.mulDiv(refPercent, collected, 10 ** 4)
            : 0;
        uint256 amount = collected - refFee;
        if (amount == adminWithdrawn) revert NoAmountIsAvailableToWithdraw();
        uint256 available = amount - adminWithdrawn;
        if (settings.feeTo == address(0)) {
            settings.feeTo.sendValue(available);
        } else {
            uint256 fee = MathUpgradeable.mulDiv(
                feePercent,
                collected,
                10 ** 4
            );
            uint256 finalFee = fee - feeWithdrawn;
            settings.feeTo.sendValue(available - finalFee);
            feeDestination.sendValue(finalFee);
            feeWithdrawn = fee;
        }
        adminWithdrawn = amount;
    }

    function availableAdminEarnings() external view returns(uint256){
        uint256 refPercent = settings.refFee;
        if (collected == 0) revert NoAmountIsAvailableToWithdraw();
        uint256 refFee = refPercent > 0
            ? MathUpgradeable.mulDiv(refPercent, collected, 10 ** 4)
            : 0;
        uint256 amount = collected - refFee;
        if (amount == adminWithdrawn) revert NoAmountIsAvailableToWithdraw();
        uint256 available = amount - adminWithdrawn;
        if (settings.feeTo == address(0)) {
            return available;
        } else {
            uint256 fee = MathUpgradeable.mulDiv(
                feePercent,
                collected,
                10 ** 4
            );
            return available - fee;
        }
    }

    function withdrawRef(address payable to) external {
        uint256 amount = refs[_msgSender()];
        uint256 withdrawn = refWithdrawals[_msgSender()];
        uint256 refPercent = settings.refFee;
        if (amount == 0) revert NoAmountIsAvailableToWithdraw();
        if (refPercent == 0) revert ReferralsAreDisabled();
        uint256 fee = MathUpgradeable.mulDiv(refPercent, amount, 10 ** 4);
        if (fee == withdrawn) revert NoAmountIsAvailableToWithdraw();
        uint256 available = fee - withdrawn;
        to.sendValue(available);
        refWithdrawals[_msgSender()] = fee;
        emit ReferralEarnings(_msgSender(), to, available);
    }

    function availableRefEarnings(
        address user
    ) external view returns (uint256) {
        if (refs[user] == 0) return 0;
        uint256 refPercent = settings.refFee;
        uint256 fee = MathUpgradeable.mulDiv(refPercent, refs[user], 10 ** 4);
        if (fee <= refWithdrawals[user]) return 0;
        return fee - refWithdrawals[user];
    }

    function totalSupply() external view returns (uint256) {
        return _tokenIdCounter.current();
    }

  

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721ReceiverUpgradeable(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    data
                )
            returns (bytes4 retval) {
                return
                    retval ==
                    IERC721ReceiverUpgradeable.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    /// @solidity memory-safe-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }
}

