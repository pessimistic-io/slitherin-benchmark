// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

library Lib_Type {
    struct Token {
        uint256 chainId;
	address tokenAddress;
    }

    struct LP {
        bytes32 lpId;
	Token baseToken;
	Token token_1;
	Token token_2;
	address maker;
	uint256 gasCompensation;
	uint256 txFeeRatio; // percentage * 100000000
	uint256 startTimestamp; // 0 represents the lp is always available
	uint256 stopTimestamp; // 0 represents the lp will never stop
    }

    struct LpKey {
	bytes32 lpId;
	bool isDeleted;
    }

    function getLpId(Token memory token_1,
		     Token memory token_2,
		     address maker) internal pure returns (bytes32) {
        if (token_1.chainId < token_2.chainId) {
            return keccak256(abi.encodePacked(token_1.chainId,
					      token_1.tokenAddress,
					      token_2.chainId,
					      token_2.tokenAddress,
					      maker));
        } else {
   	    return keccak256(abi.encodePacked(token_2.chainId,
					      token_2.tokenAddress,
					      token_1.chainId,
					      token_1.tokenAddress,
					      maker));
	}
    }
}

