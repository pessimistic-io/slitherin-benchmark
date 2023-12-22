// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./FeeSubsidy.sol";

interface IBurnToken {
    function burn(address from, uint256 amount) external;

    function burnNFT(address from, uint[] memory ids, uint[] memory values) external;
    function burnNFT(uint id) external;
}

contract MockICrossSC is ICrossSC {
    uint256 public contractFee;
    uint256 public agentFee;
    address public mockTokenManager;

    enum TokenCrossType {ERC20, ERC721, ERC1155}

    function setMockTokenManager(address _mockTokenManager) public {
        mockTokenManager = _mockTokenManager;
    }

    function setFees(uint256 _contractFee, uint256 _agentFee) public {
        contractFee = _contractFee;
        agentFee = _agentFee;
    }

    function getFee(GetFeesParam memory) external view override returns(GetFeesReturn memory fee) {
        return GetFeesReturn({contractFee: contractFee, agentFee: agentFee});
    }

    function bytesToAddress(bytes memory b) internal pure returns (address addr) {
        assembly {
            addr := mload(add(b,20))
        }
    }

    function userLock(bytes32, uint tokenPairID, uint value, bytes memory) external payable override {
        bytes memory fromAccount;
        (, fromAccount, , ) = ITokenManager(mockTokenManager).getTokenPairInfo(tokenPairID);
        address fromToken = bytesToAddress(fromAccount);
        if (fromToken != address(0)) {
            IERC20(fromToken).transferFrom(msg.sender, address(this), value);
            require(msg.value == contractFee, "MockICrossSC: invalid fee value");
        } else {
            require(msg.value == contractFee + value, "MockICrossSC: invalid fee and value");
        }
    }

    function userBurn(bytes32, uint tokenPairID, uint value, uint, address tokenAccount, bytes memory) external payable override {
        bytes memory toAccount;
        (, , , toAccount) = ITokenManager(mockTokenManager).getTokenPairInfo(tokenPairID);
        address toToken = bytesToAddress(toAccount);
        require(toToken == tokenAccount, "MockICrossSC: invalid burn Token");
        require(msg.value == contractFee, "MockICrossSC: invalid fee value");
        IBurnToken(toToken).burn(msg.sender, value);
    }

    function getBatchFee(uint, uint batchLength) public view returns(uint) {
        return contractFee + batchLength * contractFee / 10;
    }

    function userLockNFT(bytes32, uint tokenPairID, uint[] memory tokenIDs, uint[] memory tokenValues, bytes memory) public payable {
        uint fromChainID;
        uint toChainID;
        bytes memory fromAccount;
        (fromChainID, fromAccount, toChainID, ) = ITokenManager(mockTokenManager).getTokenPairInfo(tokenPairID);

        uint fee = getBatchFee(tokenPairID, tokenIDs.length);
        require(msg.value == fee, "fee not match");

        address fromToken = bytesToAddress(fromAccount);

        uint8 tokenCrossType = ITokenManager(mockTokenManager).mapTokenPairType(tokenPairID);
        if (tokenCrossType == uint8(TokenCrossType.ERC721)) {
            for(uint idx = 0; idx < tokenIDs.length; ++idx) {
                IERC721(fromToken).safeTransferFrom(msg.sender, address(this), tokenIDs[idx], "");
            }
        } else if(tokenCrossType == uint8(TokenCrossType.ERC1155)) {
            IERC1155(fromToken).safeBatchTransferFrom(msg.sender, address(this), tokenIDs, tokenValues, "");
        } else {
            require(false, "Invalid NFT type");
        }
    }

    function userBurnNFT(bytes32, uint tokenPairID, uint[] memory tokenIDs, uint[] memory tokenValues, address tokenAccount, bytes memory) public payable {
        uint fromChainID;
        uint toChainID;
        (fromChainID, , toChainID, ) = ITokenManager(mockTokenManager).getTokenPairInfo(tokenPairID);

        uint fee = getBatchFee(tokenPairID, tokenIDs.length);
        require(address(this).balance >= fee, "FeeSubsidy: Insufficient fee");

        require(tokenAccount != address(0), "FeeSubsidy: tokenAccount is zero address");
        uint8 tokenCrossType = ITokenManager(mockTokenManager).mapTokenPairType(tokenPairID);
        if (tokenCrossType == uint8(TokenCrossType.ERC721)) {
            for(uint idx = 0; idx < tokenIDs.length; ++idx) {
                IBurnToken(tokenAccount).burnNFT(tokenIDs[idx]);
            }
        } else if(tokenCrossType == uint8(TokenCrossType.ERC1155)) {
            IBurnToken(tokenAccount).burnNFT(msg.sender, tokenIDs, tokenValues);
        } else {
            require(false, "Invalid NFT type");
        }
    }

    function currentChainID() external pure returns (uint256) {
        return 1;
    }

    function getTokenPairFee(uint256) external pure returns(uint256) {
        return 0;
    }
}

contract MockITokenManager is ITokenManager {
    uint public fromChainID;
    bytes public fromAccount;
    uint public toChainID;
    bytes public toAccount;
    enum TokenCrossType {ERC20, ERC721, ERC1155}

    function setTokenPairInfo(uint _fromChainID, bytes memory _fromAccount, uint _toChainID, bytes memory _toAccount) public {
        fromChainID = _fromChainID;
        fromAccount = _fromAccount;
        toChainID = _toChainID;
        toAccount = _toAccount;
    }

    function getTokenPairInfo(uint) external view override returns (uint _fromChainID, bytes memory _fromAccount, uint _toChainID, bytes memory _toAccount){
        return (fromChainID, fromAccount, toChainID, toAccount);
    }

    function mapTokenPairType(uint tokenPairID) external pure returns (uint8 tokenPairType) {
        return tokenPairID == 1 ? uint8(TokenCrossType.ERC20) : uint8(TokenCrossType.ERC1155);
    }
}

