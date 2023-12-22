// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.16;

import "./AccessControl.sol";
import "./IArkenPairLongTermFactory.sol";
import "./IERC721URIProvider.sol";
import "./ArkenPairLongTerm.sol";

contract ArkenPairLongTermFactory is
    AccessControl,
    IArkenPairLongTermFactory,
    IERC721URIProvider
{
    string public baseURI;
    bytes32 public constant PAIR_CREATOR_ROLE = keccak256('PAIR_CREATOR_ROLE');

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(string memory baseURI_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        baseURI = baseURI_;
    }

    function updateBaseURI(
        string memory baseURI_
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        baseURI = baseURI_;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(
        address tokenA,
        address tokenB
    ) external override onlyRole(PAIR_CREATOR_ROLE) returns (address pair) {
        require(
            tokenA != tokenB,
            'ArkenPairLongTermFactory: IDENTICAL_ADDRESSES'
        );
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), 'ArkenPairLongTermFactory: ZERO_ADDRESS');
        require(
            getPair[token0][token1] == address(0),
            'ArkenPairLongTermFactory: PAIR_EXISTS'
        ); // single check is sufficient

        pair = address(
            new ArkenPairLongTerm{
                salt: keccak256(abi.encodePacked(token0, token1))
            }()
        );
        IArkenPairLongTerm(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        IArkenPairLongTerm(pair).pause();
        IArkenPairLongTerm(pair).setPauser(msg.sender);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}

