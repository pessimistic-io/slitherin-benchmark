// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./IERC20.sol";
import "./DataTypes.sol";
import "./IPriceRouter.sol";
import "./RBAC.sol";

/**
 * @dev     This contract is a storage of all protocols and other info for the vault
 */

contract Registry is RBAC {
    uint256 public constant PROTOCOLS_LIMIT = 12;
    uint256 public constant ITOKENS_LIMIT = 12;
    address[] public protocols;
    address[] public iTokens;

    bool public depositsPaused;

    IPriceRouter public router;

    uint256 public poolLimitSize;
    uint256 public userDepositLimit;

    mapping(address => bool) public isProtocol;
    mapping(address => bool) public isIToken;
    mapping(address => DataTypes.ProtocolSelectors) public protocolSelectors;

    event AddProtocol(address indexed protocol, DataTypes.ProtocolSelectors selectors);
    event RemoveProtocol(uint256 indexed index, address indexed protocol);
    event AddIToken(address indexed token);
    event RemoveIToken(uint256 indexed index, address indexed token);
    event SetPoolLimit(uint256 newLimit);
    event SetUserDepositLimit(uint256 newLimit);
    event SetDepositsPaused(bool depositsPaused);

    function __Registry_init(
        address[] memory _protocols,
        DataTypes.ProtocolSelectors[] memory _protocolSelectors,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _priceRouter,
        uint256 _poolLimit
    ) internal onlyInitializing {
        __RBAC_init();

        require(_protocols.length == _protocolSelectors.length, "Mismatch _protocols and _protocolSelectors arrays lengths");
        require(_rebalanceMatrixProvider != address(0), "Rebalance provider address can't be address zero");
        require(_priceRouter != address(0), "Price router address can't be address zero");

        router = IPriceRouter(_priceRouter);

        for (uint i = 0; i < _protocols.length; i++) {
            addProtocol(_protocols[i], _protocolSelectors[i]);
        }

        for (uint i = 0; i < _iTokens.length; i++) {
            addIToken(_iTokens[i]);
        }

        _grantRole(REBALANCE_PROVIDER_ROLE, _rebalanceMatrixProvider);

        _setPoolLimit(_poolLimit);
        _setUserDepositLimit(_poolLimit / 10);
    }

    /**
     * @return  address[]  the list of contracts which the vault can iterate with
     */
    function getProtocols() public view returns (address[] memory) {
        return protocols;
    }

    /**
     * @return  address[]  the list of ERC20 tokens which the vault store the balance in
     */
    function getITokens() public view returns (address[] memory) {
        return iTokens;
    }

    /**
     * @notice  allows admin to add a new protocol
     */

    function addProtocol(address protocol, DataTypes.ProtocolSelectors memory selectors) public onlyOwner {
        require(protocol != address(0), "Protocol can't be address zero");
        require(!isProtocol[protocol], "Already added");
        require(protocols.length < PROTOCOLS_LIMIT, "Protocols limit amount exceeded");

        protocols.push(protocol);
        isProtocol[protocol] = true;
        protocolSelectors[protocol] = selectors;

        emit AddProtocol(protocol, selectors);
    }

    /**
     * @notice  allows admin to remove a protocol
     */
    function removeProtocol(uint256 index) public onlyOwner {
        address protocol = protocols[index];

        isProtocol[protocol] = false;

        protocols[index] = protocols[protocols.length - 1];
        protocols.pop();

        emit RemoveProtocol(index, protocol);
    }

    /**
     * @notice  allows admin to add a new iToken to store the balance in
     */
    function addIToken(address iToken) public virtual onlyOwner {
        require(iToken != address(0), "iToken can't address zero");
        require(!isIToken[iToken], "Already added");
        require(iTokens.length < ITOKENS_LIMIT, "iTokens limit amount exceeded");

        iTokens.push(iToken);
        isIToken[iToken] = true;

        emit AddIToken(iToken);
    }

    /**
     * @notice  allows admin to remove iToken. The balance of this token should be 0.
     */
    function removeIToken(uint256 index) public onlyOwner {
        address iToken = iTokens[index];
        require(IERC20(iToken).balanceOf(address(this)) == 0, "IToken balance should be 0");

        isIToken[iToken] = false;

        iTokens[index] = iTokens[iTokens.length - 1];
        iTokens.pop();

        emit RemoveIToken(index, iToken);
    }

    function setDepositsPaused(bool _depositsPaused) external onlyOwner {
        depositsPaused = _depositsPaused;
        emit SetDepositsPaused(_depositsPaused);
    }

    modifier whenNotDepositsPause() {
        require(!depositsPaused, "Deposits on pause");
        _;
    }

    function setPoolLimit(uint256 newLimit) external onlyOwner {
        _setPoolLimit(newLimit);
    }

    function setUserDepositLimit(uint256 newLimit) external onlyOwner {
        _setUserDepositLimit(newLimit);
    }

    function _setPoolLimit(uint256 newLimit) private {
        poolLimitSize = newLimit;

        emit SetPoolLimit(newLimit);
    }

    function _setUserDepositLimit(uint256 newLimit) private {
        userDepositLimit = newLimit;

        emit SetUserDepositLimit(newLimit);
    }

    uint256[50] private __gap;
}

