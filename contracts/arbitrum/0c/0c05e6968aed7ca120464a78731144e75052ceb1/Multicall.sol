pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import "./console.sol";

interface ERC721 {
    function balanceOf(address) external view returns (uint);

    function ownerOf(uint) external view returns (address);
}

contract Multicall {
    struct Call {
        address target;
        bytes callData;
    }
    struct Result {
        bool success;
        bytes returnData;
    }

    function viewBalance(address nft, address holder) external view returns (uint) {
        return ERC721(nft).balanceOf(holder);
    }

    function viewIds(address nft, address holder) external view returns (uint[] memory returnData) {
        uint balance = ERC721(nft).balanceOf(holder);
        returnData = new uint[](balance);
        uint pos = 0;
        for (uint i = 0; i < 10053; i++) {
            try ERC721(nft).ownerOf(i) returns (address owner) {
                if (owner == holder) {
                    returnData[pos] = i;
                    pos++;
                }
                if (pos >= balance) {
                    i = 10054;
                }
            } catch {}
        }
    }

    function tryAggregateSuccesses(address nft, address holder, Call[] memory calls) public returns (Result[] memory returnData) {
        uint balance = ERC721(nft).balanceOf(holder);
        returnData = new Result[](balance);
        uint pos = 0;
        for (uint i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);

            if (success) {
                returnData[pos] = Result(success, ret);
                pos++;
            }
        }
    }

    function tryAggregate(bool requireSuccess, Call[] memory calls) public returns (Result[] memory returnData) {
        returnData = new Result[](calls.length);
        for (uint i = 0; i < calls.length; i++) {
            (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);

            if (requireSuccess) {
                require(success, "Multicall2 aggregate: call failed");
            }

            returnData[i] = Result(success, ret);
        }
    }

    function bytesToAddress(bytes memory bys) private pure returns (address addr) {
        assembly {
            addr := mload(add(bys, 32))
        }
    }
}

