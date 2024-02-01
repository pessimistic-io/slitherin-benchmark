// SPDX-License-Identifier: BUSL-1.1
// Reality NFT Contracts

pragma solidity 0.8.9;

import "./IRealityProperties.sol";
import "./RealityPropertiesERC20Adapter.sol";
import "./Create2.sol";
import "./Strings.sol";
import "./IERC2981Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ERC1155SupplyUpgradeable.sol";

/**
* @title Manages shares of properties in Reality realm 
* @notice This contract is based on ERC1155 with each token representing a single property.
* Total supply of each token varies, but once minted it's immuttable.
* The contract acts as aggregate for ERC20 adapters. Each adapter represents a single ERC1155 token,
* and allows for fractional operations. Also being compatible with ERC20 it allows trades on DEXes.
* For consistency `integer` amount means value without fractional part. 'Fractional' amount is full value
* with integer and fractional parts.
* Every public function uses integer only, unless specified otherwise.
* @dev The token amounts are internaly represented as it's full value, i.e. integer and fractional part.
* tokenId == 0 is not supported because of _adapterMapper
*/
abstract contract RealityProperties is IERC2981Upgradeable, ERC1155SupplyUpgradeable, AccessControlUpgradeable, IRealityProperties {
    using AddressUpgradeable for address;
    using Strings for uint256;

    /**
     * Royalties as basis points
     */
    uint96 public constant MAX_ROYALTIES_BPS = 1000; // 10%
    uint96 public constant DEFAULT_ROYALTIES_BPS = 200; // 2%

    uint96 public royaltiesBps;

    /**
     * Address that receives royalties
     */
    address public royaltiesReceiver;

    /**
     * Mapping: adapter addresss -> token id
     * 
     * @dev The opposite mappinging is done in-flight using create2
     */
    mapping(address => uint256) internal _adapterMapper;

    /**
     * Address that the main implementatiton for ERC20 is held, basis for all proxies
     */
    address public erc20AdapterImplementation;

    /**
     * Additional contract level metadata, supported by OpenSea
     */
    string public contractURI;

    /**
     * @notice Is metadata sealed.
     * Metadata cannot be updated after being sealed.
     * @dev When metadata are sealed, the contract uri and base uri cannot be changed.
     * When metadata are sealed, uri for already existing tokens cannot be updated.
     * But the individual token uries can be set for new tokens after metadata are sealed. But only once.
     */
    bool public metadataSealed;

    /**
     * @notice Individual token uris, if not set, then use the base uri {_uri}.
     * @dev The value can be "", "a", "b", or a string of length greater than 1.
     * "" means that token does not exist.
     * "a" means use the base uri, it is the default value before metadata are sealed.
     * "b" means that uri is not yet set, it is the default value after metadata are sealed. Calculated uri is empty.
     * A string longer than 1 means the individual uri token itself.
     */
    mapping(uint256 => string) internal _uris;

    /**
     * @dev Mapping from token ID to account balances. Supports fractionals.
     * Replaces {ERC1155Upgradeable-_balances}.
     * Every function in ERC1155Upgradeable that uses _balance is overridden in this contract to use _fractionalBalances.
     * So _balances is not used.
     */
    mapping(uint256 => mapping(address => uint256)) internal _fractionalBalances;

    event NewAdapter(uint256 indexed id, address indexed adapter);
    event MetadataSealed();
    event ContractURI();
    event UriSet(uint256 indexed id);
    event BaseUriSet();
    event DefaultRoyaltySet(address indexed receiver, uint96 feeNumerator);

    string public constant VERSION = "1.0";
    bytes32 public constant METADATA_MANAGER = keccak256("METADATA_MANAGER");
    bytes32 public constant ROYALTIES_MANAGER = keccak256("ROYALTIES_MANAGER");
    uint256 internal constant DECIMALS_MULTIPLIER = 10 ** 18;

    // solhint-disable-next-line func-name-mixedcase
    function __RealityProperties_init(string memory uri_, string memory contractUri_, address royaltiesReceiver_) internal onlyInitializing {
        __ERC1155_init(uri_);
        emit BaseUriSet();
        __RealityProperties_init_unchained(contractUri_, royaltiesReceiver_);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __RealityProperties_init_unchained(string memory contractUri_, address royaltiesReceiver_) internal onlyInitializing {
        require(royaltiesReceiver_ != address(0), "Royalty receiver is zero");
        emit DefaultRoyaltySet(royaltiesReceiver_, royaltiesBps);
        erc20AdapterImplementation = address(new RealityPropertiesERC20Adapter());
        contractURI = contractUri_;
        royaltiesReceiver = royaltiesReceiver_;
        royaltiesBps = DEFAULT_ROYALTIES_BPS;
        emit DefaultRoyaltySet(royaltiesReceiver_, royaltiesBps);
        emit ContractURI();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(METADATA_MANAGER, msg.sender);
        _grantRole(ROYALTIES_MANAGER, msg.sender);
    }

    // **********************************
    // ******** ERC1155 Interface *******
    // **********************************

    /**
     * @dev Removes fractional part from internal representation of account balance
     */
    function balanceOf(address account, uint256 tokenId)
        public
        view
        virtual
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        returns (uint256) {
        require(account != address(0), "ERC1155: balance query for the zero address");
        return _fractionalBalances[tokenId][account] / DECIMALS_MULTIPLIER;
    }

    /**
     * @dev Removes fractional part from internal representation of account balances
     */
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        public
        view
        virtual
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        returns (uint256[] memory) {
        require(accounts.length == ids.length, "ERC1155: accounts and ids length mismatch");

        uint256[] memory batchBalances = new uint256[](accounts.length);

        /// @dev the outcome of balanceOf() has the fractional part already removed
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }

        return batchBalances;
    }


    // **********************************
    // ***** Royalties Management ******
    // **********************************
    modifier royaltyWithinLimit(uint96 feeNumerator) {
        require(feeNumerator <= MAX_ROYALTIES_BPS, "Royalty fraction over the limit");
        _;
    }

    /**
     * @dev See {ERC2981Upgradeable-_setDefaultRoyalty}.
     * We allow only for setting the default royalty. Royalties for every token are the same.
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external virtual royaltyWithinLimit(feeNumerator) onlyRole(ROYALTIES_MANAGER) {
        require(receiver != address(0), "Royalty receiver is zero");
        royaltiesReceiver = receiver;
        royaltiesBps = feeNumerator;
        emit DefaultRoyaltySet(receiver, feeNumerator);
    }

    function royaltyInfo(uint256, uint256 salePrice) external view virtual override returns (address, uint256) {
        uint256 royaltyAmount = salePrice * royaltiesBps / 10000;
        return (royaltiesReceiver, royaltyAmount);
    }

    // **********************************
    // ***** ERC20Adapter Creation ******
    // **********************************

    /**
     * @dev Requires that the new created address equals to the pre-calculated address.
     * The adapter must not exists before. 
     *
     * Creates new ERC20 adapter for the specified token id
     *
     * Emits a `NewAdapter` event.
     */
    function _createAdapter(uint256 tokenId) internal returns (address) {
        address expectedAddress = _computeAddress(tokenId, erc20AdapterImplementation);
        assert(_adapterMapper[expectedAddress] == 0); // Adapter already deployed

        address adapterAddress = _deploy(tokenId, erc20AdapterImplementation);
        assert(expectedAddress == adapterAddress); // Invalid contract address

        _adapterMapper[adapterAddress] = tokenId;
        emit NewAdapter(tokenId, adapterAddress);

        return adapterAddress;
    }

    function _adapterExists(uint256 tokenId) internal view returns (bool) {
        require(tokenId > 0, "ERC1155: token id zero is not supported");
        address expectedAddress = _computeAddress(tokenId, erc20AdapterImplementation);
        return _adapterMapper[expectedAddress] == tokenId;
    }

    /**
     * @dev The address is computed using create2 method based on token id and contract address
     */
    function _computeAddress(uint256 tokenId, address implementation) internal view returns (address) {
        return
            Create2.computeAddress(
                keccak256(abi.encodePacked(tokenId)),
                keccak256(_getContractCreationCode(implementation)),
                address(this)
            );
    }

    /**
     * @dev The address is computed using create2 method based on token id and contract address
     */
    function _deploy(uint256 tokenId, address implementation) internal returns(address) {
        address minimalProxy = Create2.deploy(
            0,
            keccak256(abi.encodePacked(tokenId)),
            _getContractCreationCode(implementation)
        );

        return minimalProxy;
    }

    /**
     * @dev Standard minimal proxy, see https://blog.openzeppelin.com/deep-dive-into-the-minimal-proxy-contract/
     */
    function _getContractCreationCode(address implementation) internal pure returns (bytes memory) {
        bytes10 creation = 0x3d602d80600a3d3981f3;
        bytes10 prefix = 0x363d3d373d3d3d363d73;
        bytes20 targetBytes = bytes20(implementation);
        bytes15 suffix = 0x5af43d82803e903d91602b57fd5bf3;

        return abi.encodePacked(creation, prefix, targetBytes, suffix);
    }

    /**
     * Using token id returns ERC20 adapter address
     */
    function getAdapterAddress(uint256 tokenId_) external view returns (address){
        return _computeAddress(tokenId_, erc20AdapterImplementation);
    }

    // **********************************
    // ***** ERC20Adapter Interface *****
    // **********************************

    /**
     * Returns total supply as fractional amount
     * 
     * @dev gasless transfers are not supported for adapters, msg.sender is used
     */
    function fractionalTransferByAdapter(address from, address to, uint256 fractionalAmount) external {
        uint256 tokenId = getTokenId(msg.sender);
        _transferFrom(from, to, tokenId, fractionalAmount);
    }

    /**
     * Returns total supply as fractional amount
     */
    function fractionalTotalSupply(address erc20adapter) external view returns (uint256) {                   
        uint256 tokenId = getTokenId(erc20adapter);
        return super.totalSupply(tokenId) * DECIMALS_MULTIPLIER;
    }

    /**
     * Returns account balance as fractional amount
     */
    function fractionalBalanceOf(address account, uint256 tokenId) external view returns (uint256){
        require(account != address(0), "RealityProperties: balance query for the zero address");
        return _fractionalBalances[tokenId][account];
    }

    /**
     * Using ERC20 adapter address returns token id
     */
    function getTokenId(address erc20adapter) public view returns (uint256)
    {
        uint256 tokenId = _adapterMapper[erc20adapter];
        require(tokenId > 0, "RealityProperties: Token does not exist");
        return tokenId;
    }

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     * gasless transfers are not supported for adapters, msg.sender is used
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     */
    function _transferFrom(
        address from,
        address to,
        uint256 id,
        uint256 fractionalAmount
    ) internal virtual {
        require(to != address(0), "RealityProperties: invalid address");
        require(id > 0, "ERC1155: token id zero is not supported");

        address operator = msg.sender;

        uint256 fromBalance = _fractionalBalances[id][from];

        // these artificial events make things compliant with balanceOf() logic
        // balanceOf() cuts fractional part
        if ((fromBalance % DECIMALS_MULTIPLIER) < (fractionalAmount % DECIMALS_MULTIPLIER)) {
            emit TransferSingle(operator, from, address(0), id, 1);  // burn
        }
        if ((_fractionalBalances[id][to] % DECIMALS_MULTIPLIER) + (fractionalAmount % DECIMALS_MULTIPLIER) >= DECIMALS_MULTIPLIER) {
            emit TransferSingle(operator, address(0), to, id, 1);  // mint
        }

        require(fromBalance >= fractionalAmount, "ERC1155AggregateV2: insufficient balance");
        unchecked {
            _fractionalBalances[id][from] = fromBalance - fractionalAmount;
        }
        _fractionalBalances[id][to] += fractionalAmount;

        emit TransferSingle(operator, from, to, id, fractionalAmount / DECIMALS_MULTIPLIER);
    }

    // **********************************
    // ** ERC1155Upgradeable Overrides **
    // **********************************

    /**
     * @dev See {ERC1155Upgradeable-_safeTransferFrom}.
     * The function is copied and slightly modified to support fractionals.
     */
    function _safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: transfer to the zero address");
        require(id > 0, "ERC1155: token id zero is not supported");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, __asSingletonArray(id), __asSingletonArray(amount), data);

        uint256 fractionalAmount = amount * DECIMALS_MULTIPLIER;
        uint256 fromBalance = _fractionalBalances[id][from];
        require(fromBalance >= fractionalAmount, "ERC1155: insufficient balance for transfer");
        unchecked {
            _fractionalBalances[id][from] = fromBalance - fractionalAmount;
        }
        _fractionalBalances[id][to] += fractionalAmount;

        /// @dev * change * hide fractional part in the public event
        emit TransferSingle(operator, from, to, id, amount);

        __doSafeTransferAcceptanceCheck(operator, from, to, id, amount, data);
    }

    /**
     * @dev See {ERC1155Upgradeable-_safeBatchTransferFrom}.
     * The function is copied and slightly modified to support fractionals.
     */
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        require(to != address(0), "ERC1155: transfer to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            require(id > 0, "ERC1155: token id zero is not supported");

            uint256 fractionalAmount = amounts[i] * DECIMALS_MULTIPLIER;

            uint256 fromBalance = _fractionalBalances[id][from];
            require(fromBalance >= fractionalAmount, "ERC1155: insufficient balance for transfer");
            unchecked {
                _fractionalBalances[id][from] = fromBalance - fractionalAmount;
            }
            _fractionalBalances[id][to] += fractionalAmount;
        }

        emit TransferBatch(operator, from, to, ids, amounts);

        __doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, amounts, data);
    }

    /**
     * @dev See {ERC1155Upgradeable-_mint}.
     * Do not use implementation from ERC1155Upgradeable.
     * Copy from ERC1155Upgradeable and modify to support fractionals if needed.
     */
    function _mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(id > 0, "ERC1155: token id zero is not supported");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, __asSingletonArray(id), __asSingletonArray(amount), data);

        uint256 fractionalAmount = amount * DECIMALS_MULTIPLIER;
        _fractionalBalances[id][to] += fractionalAmount;
        initialUri(id);
        emit TransferSingle(operator, address(0), to, id, amount);

        __doSafeTransferAcceptanceCheck(operator, address(0), to, id, amount, data);
    }

    /**
     * @dev See {ERC1155Upgradeable-_mintBatch}.
     * Do not use implementation from ERC1155Upgradeable.
     * Copy from ERC1155Upgradeable and modify to support fractionals if needed.
     */
    function _mintBatch(
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        require(to != address(0), "ERC1155: mint to the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");
        for (uint256 i = 0; i < ids.length; i++) {
            require(ids[i] > 0, "ERC1155: token id zero is not supported");
        }

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), to, ids, amounts, data);

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 fractionalAmount = amounts[i] * DECIMALS_MULTIPLIER;
            _fractionalBalances[ids[i]][to] += fractionalAmount;
            initialUri(ids[i]);
        }

        emit TransferBatch(operator, address(0), to, ids, amounts);

        _afterTokenTransfer(operator, address(0), to, ids, amounts, data);

        __doSafeBatchTransferAcceptanceCheck(operator, address(0), to, ids, amounts, data);
    }

    /**
     * @dev See {ERC1155Upgradeable-_burn}.
     * Do not use implementation from ERC1155Upgradeable.
     * Copy from ERC1155Upgradeable and modify to support fractionals if needed.
     */
    function _burn(
        address from,
        uint256 id,
        uint256 amount
    ) internal virtual override{
        require(from != address(0), "ERC1155: burn from the zero address");
        require(id > 0, "ERC1155: token id zero is not supported");

        address operator = _msgSender();
        uint256[] memory ids = __asSingletonArray(id);
        uint256[] memory amounts = __asSingletonArray(amount);

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        uint256 fractionalAmount = amount * DECIMALS_MULTIPLIER;
        uint256 fractionalFromBalance = _fractionalBalances[id][from];
        require(fractionalFromBalance >= fractionalAmount, "ERC1155: burn amount exceeds balance");
        unchecked {
            _fractionalBalances[id][from] = fractionalFromBalance - fractionalAmount;
        }

        emit TransferSingle(operator, from, address(0), id, amount);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /**
     * @dev See {ERC1155Upgradeable-_burnBatch}.
     * Do not use implementation from ERC1155Upgradeable.
     * Copy from ERC1155Upgradeable and modify to support fractionals if needed.
     */
    function _burnBatch(
        address from,
        uint256[] memory ids,
        uint256[] memory amounts
    ) internal virtual override{
        require(from != address(0), "ERC1155: burn from the zero address");
        require(ids.length == amounts.length, "ERC1155: ids and amounts length mismatch");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, from, address(0), ids, amounts, "");

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            require(id > 0, "ERC1155: token id zero is not supported");

            uint256 fractionalAmount = amounts[i] * DECIMALS_MULTIPLIER;

            uint256 fractionalFromBalance = _fractionalBalances[id][from];
            require(fractionalFromBalance >= fractionalAmount, "ERC1155: burn amount exceeds balance");
            unchecked {
                _fractionalBalances[id][from] = fractionalFromBalance - fractionalAmount;
            }
        }

        emit TransferBatch(operator, from, address(0), ids, amounts);

        _afterTokenTransfer(operator, from, address(0), ids, amounts, "");
    }

    /**
     * @dev See {ERC1155Upgradeable-_doSafeTransferAcceptanceCheck}.
     * The function is literally copied, because of the visibility: private.
     */
    function __doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) internal {
        if (to.isContract()) {
            try IERC1155ReceiverUpgradeable(to).onERC1155Received(operator, from, id, amount, data) returns (bytes4 response) {
                if (response != IERC1155ReceiverUpgradeable.onERC1155Received.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    /**
     * @dev See {ERC1155Upgradeable-_doSafeBatchTransferAcceptanceCheck}.
     * The function is literally copied, because of the visibility: private.
     */
    function __doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal {
        if (to.isContract()) {
            try IERC1155ReceiverUpgradeable(to).onERC1155BatchReceived(operator, from, ids, amounts, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155ReceiverUpgradeable.onERC1155BatchReceived.selector) {
                    revert("ERC1155: ERC1155Receiver rejected tokens");
                }
            } catch Error(string memory reason) {
                revert(reason);
            } catch {
                revert("ERC1155: transfer to non ERC1155Receiver implementer");
            }
        }
    }

    /**
     * @dev See {ERC1155Upgradeable-_asSingletonArray}.
     * The function is literally copied, because of the visibility: private.
     */
    function __asSingletonArray(uint256 element) internal pure returns (uint256[] memory) {
        uint256[] memory array = new uint256[](1);
        array[0] = element;

        return array;
    }

    // **********************************
    // *********** ERC165 ***************
    // **********************************

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlUpgradeable, ERC1155Upgradeable, IERC165Upgradeable) returns (bool) {
        return ERC1155Upgradeable.supportsInterface(interfaceId)
            || AccessControlUpgradeable.supportsInterface(interfaceId)
            || interfaceId == type(IERC2981Upgradeable).interfaceId;
    }

    // **********************************
    // ********* Metadata ***************
    // **********************************

    modifier onlyMetadataManager() {
        require(hasRole(METADATA_MANAGER, msg.sender), "RealityProperties: metadata modification is not authorized");
        _;
    }

    modifier onlyNotSealed() {
        require(!metadataSealed, "RealityProperties: metadata sealed");
        _;
    }

    /**
     * @dev metadata cannot be modified after that, including individual uris, the base uri, the contract uri
     */
    function sealMetadata() external onlyMetadataManager onlyNotSealed {
        metadataSealed = true;
        emit MetadataSealed();
    }

    /**
     * @dev sets contract level uri, supported by OpenSea
     * @param contractUri_ can be empty ""
     */
    function setContractURI(string memory contractUri_) external onlyMetadataManager onlyNotSealed {
        contractURI = contractUri_;
        emit ContractURI();
    }

    function initialUri(uint256 id) internal {
        if (bytes(_uris[id]).length == 0) {  // first mint
            if (!metadataSealed) {
                _uris[id] = "a";
            } else {
                _uris[id] = "b";
            }
        }
    }

    /**
     * @dev sets individual uri for a given token id
     * @param uri_ can be empty ""
     */
    function setUri(uint256 id, string memory uri_) external onlyMetadataManager {
        require(bytes(uri_).length != 1, "RealityProperties: invalid uri");
        if (bytes(uri_).length == 0) {
            require(!metadataSealed, "RealityProperties: metadata sealed");
            _uris[id] = "a";
        } else {
            if (!metadataSealed) {
                _uris[id] = uri_;
            } else {
                require(bytes(_uris[id]).length == 0 || keccak256(bytes(_uris[id])) == keccak256(bytes("b")), "RealityProperties: metadata sealed");
                _uris[id] = uri_;
            }
        }
        emit UriSet(id);
    }

    /**
     * @dev sets the base uri for all tokens without an individual uri
     * @param uri_ can be empty ""
     */
    function setBaseUri(string memory uri_) external onlyMetadataManager onlyNotSealed {
        _setURI(uri_);
        emit BaseUriSet();
    }

    /**
     * @notice calculate token uri
     * @dev an individual or from the base uri
     */
    function uri(uint256 id) public view override returns (string memory) {
        string memory uri_ = _uris[id];
        require(bytes(uri_).length > 0, "RealityProperties: token id never sealed and uri never set");
        if (bytes(uri_).length > 1) {
            return uri_;
        }
        if (keccak256(bytes(uri_)) == keccak256(bytes("b"))) {
            return "";
        }
        // this is base uri, does not depend on tokenId
        uri_ = super.uri(id);
        return bytes(uri_).length > 0 ? string(abi.encodePacked(uri_, id.toString(), ".json")) : "";
    }
}

