// SPDX-License-Identifier: MIT
pragma solidity =0.8.10;

import "./AntfarmPair.sol";
import "./AntfarmAtfPair.sol";
import "./AntfarmFactoryErrors.sol";

/// @title Antfarm Factory
/// @notice The Factory is used to create new Pair contracts for each unique ERC20 token pair
contract AntfarmFactory is IAntfarmFactory {
    uint16[8] public possibleFees = [10, 50, 100, 150, 250, 500, 750, 1000];
    address[] public allPairs;
    address public antfarmToken;

    mapping(address => mapping(address => mapping(uint16 => address)))
        public getPair;

    mapping(address => mapping(address => uint16[8])) public feesForPair;

    constructor(address _antfarmToken) {
        require(_antfarmToken != address(0), "NULL_ATF_ADDRESS");
        antfarmToken = _antfarmToken;
    }

    /// @notice Get list of fees for existing Antfarm Pair of a specific pair
    /// @param _token0 token0 from the pair
    /// @param _token1 token1 from the pair
    /// @return uint16 Fixed fees array
    function getFeesForPair(address _token0, address _token1)
        external
        view
        override
        returns (uint16[8] memory)
    {
        return feesForPair[_token0][_token1];
    }

    /// @notice Get total number of Antfarm Pairs
    /// @return uint Number of created pairs
    function allPairsLength() public view returns (uint256) {
        return allPairs.length;
    }

    /// @notice Get Antfarm Pairs addresses
    /// @param startIndex Index of the first pair to query
    /// @param numOfPairs Number of pairs to be queried
    /// @return pairs Addresses of created pairs
    /// @return newIndex New index for chained calls
    function getPairs(uint256 startIndex, uint256 numOfPairs)
        external
        view
        returns (address[] memory pairs, uint256 newIndex)
    {
        if (numOfPairs > allPairsLength() - startIndex) {
            numOfPairs = allPairsLength() - startIndex;
        }

        pairs = new address[](numOfPairs);
        for (uint256 i; i < numOfPairs; ++i) {
            pairs[i] = allPairs[startIndex + i];
        }

        newIndex = startIndex + numOfPairs;
    }

    /// @notice Get all possible fees
    /// @return uint16[8] List of possible fees
    function getPossibleFees() external view returns (uint16[8] memory) {
        return possibleFees;
    }

    /// @notice Create new Antfarm Pair
    /// @param tokenA token0 to be used for the new Antfarm Pair
    /// @param tokenB token1 to be used for the new Antfarm Pair
    /// @param fee Fee to be used in the new Antfarm Pair
    /// @return address The address of the deployed Antfarm Pair
    function createPair(
        address tokenA,
        address tokenB,
        uint16 fee
    ) external returns (address) {
        uint16 feeIndex = validateFee(fee);
        if (tokenA == tokenB) revert IdenticalAddresses();
        address token0;
        address token1;
        if (tokenA == antfarmToken || tokenB == antfarmToken) {
            (token0, token1) = tokenA == antfarmToken
                ? (antfarmToken, tokenB)
                : (antfarmToken, tokenA);
            if (token1 == address(0)) revert ZeroAddress(); // antfarmToken can't be 0 but other could
            if (fee == 1000) revert ForbiddenFee();
        } else {
            (token0, token1) = tokenA < tokenB
                ? (tokenA, tokenB)
                : (tokenB, tokenA);
            if (token0 == address(0)) revert ZeroAddress();
        }
        if (getPair[token0][token1][fee] != address(0)) revert PairExists();

        address pair;
        bytes memory bytecode = token0 == antfarmToken
            ? type(AntfarmAtfPair).creationCode
            : type(AntfarmPair).creationCode;
        bytes32 salt = keccak256(
            abi.encodePacked(token0, token1, fee, antfarmToken)
        );
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        getPair[token0][token1][fee] = pair;
        getPair[token1][token0][fee] = pair;
        writeFee(token0, token1, feeIndex);
        allPairs.push(pair);

        token0 == antfarmToken
            ? IAntfarmAtfPair(pair).initialize(token0, token1, fee)
            : IAntfarmPair(pair).initialize(token0, token1, fee, antfarmToken);
        emit PairCreated(token0, token1, pair, fee, allPairs.length);
        return pair;
    }

    // updates the fee array for a pair with the fee amount in its index
    function writeFee(
        address token0,
        address token1,
        uint16 index
    ) internal {
        uint16[8] memory fees = feesForPair[token0][token1];
        fees[index] = possibleFees[index];
        feesForPair[token0][token1] = fees;
        feesForPair[token1][token0] = fees;
    }

    // check the fee provided is one of the available ones
    function validateFee(uint16 fee) internal view returns (uint16) {
        for (uint16 i; i < 8; ++i) {
            if (fee == possibleFees[i]) {
                return i;
            }
        }
        revert IncorrectFee();
    }
}

