// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import "./IERC20.sol";
import "./DataTypes.sol";
import "./IPriceRouter.sol";
import "./RBAC.sol";

/**
 * @dev     This contract is a storage of all positions and other info for the vault
 */

contract Registry is RBAC {
    uint256 public constant POSITIONS_LIMIT = 12;
    uint256 public constant ITOKENS_LIMIT = 12;
    address[] public positions;
    address[] public iTokens;

    bool public depositsPaused;

    IPriceRouter public immutable router;

    uint256 public poolLimitSize;
    uint256 public userDepositLimit;
    mapping(address => bool) public isAdaptorSetup;

    event PositionAdded(address position, address admin);
    event ITokenAdded(address token, address admin);
    event PositionRemoved(address position, address admin);
    event ITokenRemoved(address position, address admin);
    event Whitelisted(address user, address admin);
    event SetPoolLimit(uint256 newLimit);
    event SetUserDepositiLimit(uint256 newLimit);
    event SetPause(bool depositsPaused);

    constructor(
        address[] memory _positions,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _priceRouter,
        address[] memory _whitelist,
        uint256 _poolLimit
    ) {
        require(_rebalanceMatrixProvider != address(0), "Rebalance provider address can't be address zero");
        require(_priceRouter != address(0), "Price router address can't be address zero");
        router = IPriceRouter(_priceRouter);

        for (uint i = 0; i < _positions.length; i++) {
            addPosition(_positions[i]);
        }
        for (uint i = 0; i < _iTokens.length; i++) {
            addIToken(_iTokens[i]);
        }
        _grantRole(REBALANCE_PROVIDER_ROLE, _rebalanceMatrixProvider);

        for (uint256 i = 0; i < _whitelist.length; i++) {
            _grantRole(WHITELISTED_ROLE, _whitelist[i]);
        }
        _setPoolLimit(_poolLimit);
        _setUserDepositLimit(_poolLimit / 50);
    }

    /**
     * @return  address[]  the list of contracts which the vault can iterate with
     */
    function getPositions() public view returns (address[] memory) {
        return positions;
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

    function addPosition(address position) public onlyOwner {
        require(position != address(0), "Position can't be address zero");
        require(!isAdaptorSetup[position], "Already added");
        require(positions.length < POSITIONS_LIMIT, "Positions limit amount exceeded");

        positions.push(position);
        isAdaptorSetup[position] = true;

        emit PositionAdded(position, msg.sender);
    }

    /**
     * @notice  allows admin to remove a protocol
     */
    function removePosition(uint256 index) public onlyOwner {
        address positionAddress = positions[index];
        isAdaptorSetup[positionAddress] = false;
        for (uint256 i = index; i < positions.length - 1; i++) {
            positions[i] = positions[i + 1];
        }
        positions.pop();

        emit PositionRemoved(positionAddress, msg.sender);
    }

    /**
     * @notice  allows admin to add a new iToken to store the balance in
     */
    function addIToken(address token) public virtual onlyOwner {
        require(token != address(0), "Token can't address zero");
        require(!isAdaptorSetup[token], "Already added");
        require(iTokens.length < ITOKENS_LIMIT, "iTokens limit amount exceeded");

        iTokens.push(token);
        isAdaptorSetup[token] = true;

        emit ITokenAdded(token, msg.sender);
    }

    /**
     * @notice  allows admin to remove iToken. The balance of this token should be 0.
     */
    function removeIToken(uint256 index) public onlyOwner {
        address positionAddress = iTokens[index];
        require(IERC20(positionAddress).balanceOf(address(this)) == 0, "Itoken balance should be 0");
        isAdaptorSetup[positionAddress] = false;

        for (uint256 i = index; i < iTokens.length - 1; i++) {
            iTokens[i] = iTokens[i + 1];
        }
        iTokens.pop();

        emit ITokenRemoved(positionAddress, msg.sender);
    }

    function setPause(bool _depositsPaused) external onlyOwner {
        depositsPaused = _depositsPaused;
        emit SetPause(depositsPaused);
    }

    /**
     * @notice  once whitelist is disabled, it can't be enabled again
     */

    function disableWhitelist() external onlyOwner {
        require(!whitelistDisabled, "Already disabled");
        whitelistDisabled = true;
    }

    modifier whenNotDepositsPause() {
        require(!depositsPaused, "Deposits on pause");
        _;
    }

    function setPoolLimit(uint256 newLimit) external onlyOwner {
        _setPoolLimit(newLimit);
    }

    function setUserDepositiLimit(uint256 newLimit) external onlyOwner {
        _setUserDepositLimit(newLimit);
    }

    function _setPoolLimit(uint256 newLimit) private {
        poolLimitSize = newLimit;

        emit SetPoolLimit(newLimit);
    }

    function _setUserDepositLimit(uint256 newLimit) private {
        userDepositLimit = newLimit;

        emit SetUserDepositiLimit(newLimit);
    }
}

