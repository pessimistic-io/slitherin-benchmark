// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./Ownable.sol";
import "./IPoseidon2.sol";
import "./IMerkle.sol";

contract Merkle is Ownable, IMerkle {
    mapping(uint256 => uint256) public tree;
    uint256 public immutable LEVELS; // deepness of tree
    uint256 public m_index; // current index of the tree

    mapping(uint256 => uint256) roots;
    uint256 public rootIndex = 0;
    uint256 public constant MAX_ROOT_NUMBER = 25;

    IPoseidon2 immutable poseidon; // hashing

    // please see deployment scripts to understand how to create and instance of Poseidon contract
    constructor(uint256 _levels, address _poseidon) {
        LEVELS = _levels;
        m_index = 2**(LEVELS - 1);
        poseidon = IPoseidon2(_poseidon);
    }

    function hash(uint256 a, uint256 b)
        public
        view
        returns (uint256 poseidonHash)
    {
        poseidonHash = poseidon.poseidon([a, b]);
    }

    function insert(uint256 leaf) public onlyOwner returns (uint256) {
        tree[m_index] = leaf;
        m_index++;
        require(m_index != uint256(2)**LEVELS, "Tree is full.");

        uint256 fullCount = m_index - 2**(LEVELS - 1); // number of inserted leaves
        uint256 twoPower = logarithm2(fullCount); // number of tree levels to be updated, (e.g. if 9 => 4 levels should be updated)

        uint256 currentNodeIndex = m_index - 1;
        for (uint256 i = 1; i <= twoPower; i++) {
            currentNodeIndex /= 2;
            tree[currentNodeIndex] = hash(
                tree[currentNodeIndex * 2],
                tree[currentNodeIndex * 2 + 1]
            );
        }

        roots[rootIndex] = tree[currentNodeIndex]; // adding root to roots mapping
        rootIndex = (rootIndex + 1) % MAX_ROOT_NUMBER;

        return m_index - 1;
    }

    function getRootHash() public view returns (uint256) {
        for (uint256 i = 1; i < 2**LEVELS; i *= 2) {
            if (tree[i] != 0) {
                return tree[i];
            }
        }
        return 0;
    }

    function rootHashExists(uint256 _root) public view returns (bool) {
        uint256 i = rootIndex; // latest root hash
        do {
            if (i == 0) {
                i = MAX_ROOT_NUMBER;
            }
            i--;
            if (_root == roots[i]) {
                return true;
            }
        } while (i != rootIndex);
        return false;
    }

    function getSiblingIndex(uint256 index) public pure returns (uint256) {
        if (index == 1) {
            return 1;
        }
        return index % 2 == 1 ? index - 1 : index + 1;
    }

    function findAndRemove(uint256 dataToRemove, uint256 index)
        public
        onlyOwner
    {
        require(
            index >= 2**(LEVELS - 1) && index < m_index,
            "index out of range"
        );
        require(tree[index] == dataToRemove, "leaf doesn't match dataToRemove");

        tree[index] = 0;

        uint256 fullCount = m_index - 2**(LEVELS - 1); // number of inserted leaves
        uint256 twoPower = logarithm2(fullCount);

        uint256 currentNodeIndex = index;
        for (uint256 j = 1; j <= twoPower; j++) {
            currentNodeIndex /= 2;
            tree[currentNodeIndex] = hash(
                tree[currentNodeIndex * 2],
                tree[currentNodeIndex * 2 + 1]
            );
        }
        roots[rootIndex] = tree[currentNodeIndex]; // adding root to roots mapping
        rootIndex = (rootIndex + 1) % MAX_ROOT_NUMBER;
    }

    // this is logarithm of x with base 2.
    // instead of rounding down, this function rounds up, online other logarithm2 implementations
    function logarithm2(uint256 x) public pure returns (uint256 y) {
        assembly {
            let arg := x
            x := sub(x, 1)
            x := or(x, div(x, 0x02))
            x := or(x, div(x, 0x04))
            x := or(x, div(x, 0x10))
            x := or(x, div(x, 0x100))
            x := or(x, div(x, 0x10000))
            x := or(x, div(x, 0x100000000))
            x := or(x, div(x, 0x10000000000000000))
            x := or(x, div(x, 0x100000000000000000000000000000000))
            x := add(x, 1)
            let m := mload(0x40)
            mstore(
                m,
                0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd
            )
            mstore(
                add(m, 0x20),
                0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe
            )
            mstore(
                add(m, 0x40),
                0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616
            )
            mstore(
                add(m, 0x60),
                0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff
            )
            mstore(
                add(m, 0x80),
                0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e
            )
            mstore(
                add(m, 0xa0),
                0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707
            )
            mstore(
                add(m, 0xc0),
                0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606
            )
            mstore(
                add(m, 0xe0),
                0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100
            )
            mstore(0x40, add(m, 0x100))
            let
                magic
            := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
            let
                shift
            := 0x100000000000000000000000000000000000000000000000000000000000000
            let a := div(mul(x, magic), shift)
            y := div(mload(add(m, sub(255, a))), shift)
            y := add(
                y,
                mul(
                    256,
                    gt(
                        arg,
                        0x8000000000000000000000000000000000000000000000000000000000000000
                    )
                )
            )
        }
    }
}

