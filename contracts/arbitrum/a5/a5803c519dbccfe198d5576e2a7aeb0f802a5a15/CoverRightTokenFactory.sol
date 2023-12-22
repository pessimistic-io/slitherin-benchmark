// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.13;

import "./CoverRightToken.sol";
import "./OwnableWithoutContextUpgradeable.sol";

/**
 * @notice Factory for deploying crTokens
 *
 *         Salt as index for cover right tokens:
 *             salt = keccak256(poolId, expiry, genration)
 *
 *         Factory will record whether a crToken has been deployed
 *         Also record the generation of a specific crToken
 *         And find the address of the crToken with its salt
 *
 */
contract CoverRightTokenFactory is OwnableWithoutContextUpgradeable {
    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    address public policyCenter;

    address public incidentReport;

    address public payoutPool;

    // Salt => Already deployed
    mapping(bytes32 => bool) public deployed;

    // Salt => CR token address
    mapping(bytes32 => address) public saltToAddress;

    // Salt => Generation
    mapping(bytes32 => uint256) public generation;

    // ---------------------------------------------------------------------------------------- //
    // *************************************** Events ***************************************** //
    // ---------------------------------------------------------------------------------------- //

    event NewCRTokenDeployed(
        uint256 poolId,
        string tokenName,
        uint256 expiry,
        uint256 generation,
        address tokenAddress
    );

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(address _policyCenter, address _incidentReport)
        public
        initializer
    {
        __Ownable_init();

        policyCenter = _policyCenter;
        incidentReport = _incidentReport;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get crToken address
     *
     * @param _poolId     Pool id
     * @param _expiry     Expiry timestamp
     * @param _generation Generation of the crToken
     *
     * @return crToken CRToken address
     */
    function getCRTokenAddress(
        uint256 _poolId,
        uint256 _expiry,
        uint256 _generation
    ) external view returns (address crToken) {
        crToken = saltToAddress[
            keccak256(abi.encodePacked(_poolId, _expiry, _generation))
        ];
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    function setPayoutPool(address _payoutPool) external onlyOwner {
        require(_payoutPool != address(0), "Zero Address");
        payoutPool = _payoutPool;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Deploy Cover Right Token for a given pool
     *
     * @param _poolName   Name of Priority Pool
     * @param _poolId     Pool Id
     * @param _tokenName  Name of insured token (e.g. DEG)
     * @param _expiry     Expiry date of cover right token
     * @param _generation Generation of priority pool & crToken (1 if no liquidations occurred)
     *
     * @return newCRToken New deployed crToken address
     */
    function deployCRToken(
        string calldata _poolName,
        uint256 _poolId,
        string calldata _tokenName,
        uint256 _expiry,
        uint256 _generation
    ) external returns (address newCRToken) {
        require(msg.sender == policyCenter, "Only policy center");
        require(_expiry > 0, "Zero expiry date");

        bytes32 salt = keccak256(
            abi.encodePacked(_poolId, _expiry, _generation)
        );

        require(!deployed[salt], "Already deployed");
        deployed[salt] = true;

        bytes memory bytecode = _getCRTokenBytecode(
            _poolName,
            _poolId,
            _tokenName,
            _expiry,
            _generation
        );

        newCRToken = _deploy(bytecode, salt);
        saltToAddress[salt] = newCRToken;

        emit NewCRTokenDeployed(
            _poolId,
            _tokenName,
            _expiry,
            _generation,
            newCRToken
        );
    }

    /**
     * @notice Get cover right token deployment bytecode (with parameters)
     *
     * @param _poolName   Name of Priority Pool
     * @param _poolId     Pool Id
     * @param _tokenName  Name of insured token (e.g. DEG)
     * @param _expiry     Expiry date of cover right token
     * @param _generation Generation of priority pool (1 if no liquidations occurred)
     */
    function _getCRTokenBytecode(
        string memory _poolName,
        uint256 _poolId,
        string memory _tokenName,
        uint256 _expiry,
        uint256 _generation
    ) internal view returns (bytes memory code) {
        bytes memory bytecode = type(CoverRightToken).creationCode;

        require(policyCenter != address(0), "Zero Address");
        require(incidentReport != address(0), "Zero Address");
        require(payoutPool != address(0), "Zero Address");

        code = abi.encodePacked(
            bytecode,
            abi.encode(
                _tokenName,
                _poolId,
                _poolName,
                _expiry,
                _generation,
                policyCenter,
                incidentReport,
                payoutPool
            )
        );
    }

    /**
     * @notice Deploy function with create2
     *
     * @param code Byte code of the contract (creation code)
     * @param salt Salt for the deployment
     *
     * @return addr The deployed contract address
     */
    function _deploy(bytes memory code, bytes32 salt)
        internal
        returns (address addr)
    {
        assembly {
            addr := create2(0, add(code, 0x20), mload(code), salt)
            if iszero(extcodesize(addr)) {
                revert(0, 0)
            }
        }
    }
}

