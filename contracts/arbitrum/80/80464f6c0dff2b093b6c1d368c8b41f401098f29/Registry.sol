// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./DataTypes.sol";
import "./IPriceRouter.sol";
import "./RBAC.sol";

/**
 * @dev     This contract is a storage of all positions and other info for the vault
 */

contract Registry is RBAC {
    uint256 public POSITIONS_LIMIT = 12;
    uint256 public ITOKENS_LIMIT = 12;
    address[] public positions;
    address[] public iTokens;

    bool public depositsPaused;

    IPriceRouter public router;

    mapping(address => bool) public isAdaptorSetup;

    event PositionAdded(address position, address admin);
    event ITokenAdded(address token, address admin);
    event PositionRemoved(address position, address admin);
    event ITokenRemoved(address position, address admin);
    event Whitelisted(address user, address admin);

    constructor(
        address[] memory _positions,
        address[] memory _iTokens,
        address _rebalanceMatrixProvider,
        address _priceRouter,
        address[] memory _whitelist
    ) {
        router = IPriceRouter(_priceRouter);

        for (uint i = 0; i < _positions.length; i++) {
            addPosition(_positions[i]);
        }
        for (uint i = 0; i < _iTokens.length; i++) {
            addIToken(_iTokens[i]);
        }
        grantRole(REBALANCE_PROVIDER_ROLE, _rebalanceMatrixProvider);

        for (uint256 i = 0; i < _whitelist.length; i++) {
            grantRole(WHITELISTED_ROLE, _whitelist[i]);
        }
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

    function setPause(bool _depositsPaused) public onlyOwner {
        depositsPaused = _depositsPaused;
    }

    modifier whenNotDepositsPause() {
        require(!depositsPaused, "Deposits on pause");
        _;
    }
}

