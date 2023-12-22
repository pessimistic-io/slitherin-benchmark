// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "./OwnableUpgradeable.sol";
import "./IClearinghouse.sol";

interface ITransparentUpgradeableProxy {
    function upgradeTo(address) external;
}

// ProxyAdmin cannot access to any functions of the implementation of a proxy,
// so we have to create a helper contract to help us visit impl functions.
contract ProxyManagerHelper {
    address proxyManager;
    address clearinghouse;

    modifier onlyOwner() {
        require(
            msg.sender == proxyManager,
            "only proxyManager can access to ProxyManagerHelper."
        );
        _;
    }

    constructor() {
        proxyManager = msg.sender;
    }

    function registerClearinghouse(address _clearinghouse) external onlyOwner {
        clearinghouse = _clearinghouse;
    }

    function getClearinghouseLiq() external view returns (address) {
        return IClearinghouse(clearinghouse).getClearinghouseLiq();
    }

    function getAllBooks() external view returns (address[] memory) {
        return IClearinghouse(clearinghouse).getAllBooks();
    }

    function upgradeClearinghouseLiq(address clearinghouseLiq)
        external
        onlyOwner
    {
        IClearinghouse(clearinghouse).upgradeClearinghouseLiq(clearinghouseLiq);
    }
}

contract ProxyManager is OwnableUpgradeable {
    string constant CLEARINGHOUSE = "Clearinghouse";
    string constant CLEARINGHOUSE_LIQ = "ClearinghouseLiq";
    string constant OFFCHAIN_BOOK = "OffchainBook";

    address public submitter;
    ProxyManagerHelper proxyManagerHelper;

    string[] contractNames;
    mapping(string => address) public proxies;
    mapping(string => address) public pendingImpls;

    modifier onlySubmitter() {
        require(
            msg.sender == submitter,
            "only submitter can submit new impls."
        );
        _;
    }

    struct NewImpl {
        string name;
        address impl;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        submitter = msg.sender;
        proxyManagerHelper = new ProxyManagerHelper();
    }

    function submitImpl(string memory name, address impl)
        external
        onlySubmitter
    {
        require(pendingImpls[name] != address(0), "unsupported contract.");
        pendingImpls[name] = impl;
    }

    function updateSubmitter(address newSubmitter) external onlyOwner {
        submitter = newSubmitter;
    }

    function registerRegularProxy(string memory name, address proxy)
        external
        onlyOwner
    {
        require(proxies[name] == address(0), "already registered.");
        address impl = _getImpl(proxy);
        contractNames.push(name);
        proxies[name] = proxy;
        pendingImpls[name] = impl;
        if (_isEqual(name, CLEARINGHOUSE)) {
            proxyManagerHelper.registerClearinghouse(proxy);
            // `Clearinghouse.getClearinghouseLiq()` hasn't been implemented when registering
            // `Clearinghouse`. to make the deployment workflow less complicated, we can set
            // `pendingImpls["ClearinghouseLiq"]` to a random address, then submit the new pending
            // implementation after registration.
            pendingImpls[CLEARINGHOUSE_LIQ] = proxy;
            pendingImpls[OFFCHAIN_BOOK] = _getOffchainBooksImpl();
        }
    }

    // this function will only be used when something goes wrong where `migrateAll` cannot work anymore.
    // it could happen when we modify `Clearinghouse.getClearinghouseLiq()` or `Clearinghouse.getAllBooks()`,
    // under which case `hasPending()` will panic. we can do a force migration to `ProxyManager` to fix it.
    function forceMigrateSelf(address newImpl) external onlyOwner {
        ITransparentUpgradeableProxy(address(this)).upgradeTo(newImpl);
    }

    function migrateAll(NewImpl[] calldata newImpls) external onlyOwner {
        for (uint32 i = 0; i < newImpls.length; i++) {
            if (_isEqual(newImpls[i].name, OFFCHAIN_BOOK)) {
                _migrateOffchainBooks(newImpls[i]);
            } else if (_isEqual(newImpls[i].name, CLEARINGHOUSE_LIQ)) {
                _migrateClearinghouseLiq(newImpls[i]);
            } else {
                _migrateRegularProxy(newImpls[i]);
            }
        }
        require(!hasPending(), "still having pending impls to be migrated.");
    }

    function getProxyManagerHelper() external view returns (address) {
        return address(proxyManagerHelper);
    }

    function getContractNames() external view returns (string[] memory) {
        string[] memory ret = new string[](contractNames.length);
        for (uint32 i = 0; i < contractNames.length; i++) {
            ret[i] = contractNames[i];
        }
        return ret;
    }

    function hasPending() public view returns (bool) {
        for (uint32 i = 0; i < contractNames.length; i++) {
            string memory name = contractNames[i];
            address proxy = proxies[name];
            if (_getImpl(proxy) != pendingImpls[name]) {
                return true;
            }
        }
        if (_isClearinghouseRegistered()) {
            if (_getClearinghouseLiqImpl() != pendingImpls[CLEARINGHOUSE_LIQ]) {
                return true;
            }
            if (_getOffchainBooksImpl() != pendingImpls[OFFCHAIN_BOOK]) {
                return true;
            }
        }
        return false;
    }

    function _isEqual(string memory a, string memory b)
        internal
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _getImpl(address proxy) internal view returns (address) {
        (bool success, bytes memory returndata) = proxy.staticcall(
            hex"5c60da1b"
        );
        require(success, "failed to query impl of the proxy.");
        return abi.decode(returndata, (address));
    }

    function _getClearinghouseLiqImpl() internal view returns (address) {
        return proxyManagerHelper.getClearinghouseLiq();
    }

    function _getOffchainBooksImpl() internal view returns (address) {
        address[] memory offchainBooks = proxyManagerHelper.getAllBooks();
        address offchainBookImpl = _getImpl(offchainBooks[1]); // product 1
        for (uint32 i = 2; i < offchainBooks.length; i++) {
            require(
                _getImpl(offchainBooks[i]) == offchainBookImpl,
                "OffchainBook impls not unified."
            );
        }
        return offchainBookImpl;
    }

    function _validateImpl(address currentImpl, NewImpl calldata newImpl)
        internal
        view
    {
        require(
            pendingImpls[newImpl.name] == newImpl.impl,
            "new impls don't match with pending impls."
        );
        require(
            currentImpl != newImpl.impl,
            "current impl is already the new impl."
        );
    }

    function _migrateOffchainBooks(NewImpl calldata newImpl) internal {
        require(
            _isEqual(newImpl.name, OFFCHAIN_BOOK),
            "invalid new impl provided."
        );
        require(
            _isClearinghouseRegistered(),
            "Clearinghouse hasn't been registered."
        );
        _validateImpl(_getOffchainBooksImpl(), newImpl);
        address[] memory offchainBooks = proxyManagerHelper.getAllBooks();
        for (uint32 i = 1; i < offchainBooks.length; i++) {
            address offchainBook = offchainBooks[i];
            ITransparentUpgradeableProxy(offchainBook).upgradeTo(newImpl.impl);
        }
    }

    function _migrateRegularProxy(NewImpl calldata newImpl) internal {
        address proxy = proxies[newImpl.name];
        _validateImpl(_getImpl(proxy), newImpl);
        ITransparentUpgradeableProxy(proxy).upgradeTo(newImpl.impl);
    }

    function _migrateClearinghouseLiq(NewImpl calldata newImpl) internal {
        require(
            _isEqual(newImpl.name, CLEARINGHOUSE_LIQ),
            "invalid new impl provided."
        );
        require(
            _isClearinghouseRegistered(),
            "Clearinghouse hasn't been registered."
        );
        _validateImpl(_getClearinghouseLiqImpl(), newImpl);
        proxyManagerHelper.upgradeClearinghouseLiq(newImpl.impl);
    }

    function _isClearinghouseRegistered() internal view returns (bool) {
        return proxies[CLEARINGHOUSE] != address(0);
    }
}

