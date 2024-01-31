// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC721.sol";
import "./IERC721Enumerable.sol";
import "./IBAYCSewerPassClaim.sol";
import "./IDelegationRegistry.sol";

contract BorroMyDoggoHelper {
    address constant public SEWER_PASS_CLAIM = 0xBA5a9E9CBCE12c70224446C24C111132BECf9F1d;
    address constant public BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address constant public MAYC = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
    address constant public BAKC = 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623;
    address constant public BORRO_MY_DOGGO = 0x56B61e063f0f662588655F27B1175F4aAEBD7251;
    IDelegationRegistry delegateCash = IDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);

    struct TokenStatus {
        uint16 tokenId;
        bool delegated;
        bool claimed;
    }

    function baycTokens(address operator) external view returns(TokenStatus[] memory tokens) {
        TokenStatus[] memory tmpTokens = new TokenStatus[](512);
        uint256 statusIndex = 0;
        uint256 tmpTokenId;
        uint256[] memory checked = new uint256[](40);
        uint256 balance = IERC721(BAYC).balanceOf(operator);
        for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
            TokenStatus memory ts = getTokenStatus(operator, BAYC, IERC721Enumerable(BAYC).tokenOfOwnerByIndex(operator, tokenIndex));
            checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
            tmpTokens[statusIndex] = ts;
            statusIndex++;
        }
        IDelegationRegistry.DelegationInfo[] memory di = delegateCash.getDelegationsByDelegate(operator);
        for(uint256 i = 0;i < di.length;i++) {
            if(di[i].type_ == IDelegationRegistry.DelegationType.ALL || (di[i].type_ == IDelegationRegistry.DelegationType.CONTRACT && di[i].contract_ == BAYC)) {
                balance = IERC721(BAYC).balanceOf(di[i].vault);
                for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
                    tmpTokenId = IERC721Enumerable(BAYC).tokenOfOwnerByIndex(di[i].vault, tokenIndex);
                    if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                        TokenStatus memory ts = getTokenStatus(di[i].vault, BAYC, tmpTokenId);
                        checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                        tmpTokens[statusIndex] = ts;
                        statusIndex++;
                    }
                }
            } else if(di[i].type_ == IDelegationRegistry.DelegationType.TOKEN && di[i].contract_ == BAYC) {
                tmpTokenId = di[i].tokenId;
                if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                    TokenStatus memory ts = getTokenStatus(di[i].vault, BAYC, tmpTokenId);
                    checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                    tmpTokens[statusIndex] = ts;
                    statusIndex++;
                }
            }
        }
        tokens = new TokenStatus[](statusIndex);
        for(uint256 i = 0;i < tokens.length;i++) {
            tokens[i] = tmpTokens[i];
        }
    }

    function maycTokens(address operator) external view returns(TokenStatus[] memory tokens) {
        TokenStatus[] memory tmpTokens = new TokenStatus[](512);
        uint256 statusIndex = 0;
        uint256 tmpTokenId;
        uint256[] memory checked = new uint256[](160);
        uint256 balance = IERC721(MAYC).balanceOf(operator);
        for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
            TokenStatus memory ts = getTokenStatus(operator, MAYC, IERC721Enumerable(MAYC).tokenOfOwnerByIndex(operator, tokenIndex));
            checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
            tmpTokens[statusIndex] = ts;
            statusIndex++;
        }
        IDelegationRegistry.DelegationInfo[] memory di = delegateCash.getDelegationsByDelegate(operator);
        for(uint256 i = 0;i < di.length;i++) {
            if(di[i].type_ == IDelegationRegistry.DelegationType.ALL || (di[i].type_ == IDelegationRegistry.DelegationType.CONTRACT && di[i].contract_ == MAYC)) {
                balance = IERC721(MAYC).balanceOf(di[i].vault);
                for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
                    tmpTokenId = IERC721Enumerable(MAYC).tokenOfOwnerByIndex(di[i].vault, tokenIndex);
                    if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                        TokenStatus memory ts = getTokenStatus(di[i].vault, MAYC, tmpTokenId);
                        checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                        tmpTokens[statusIndex] = ts;
                        statusIndex++;
                    }
                }
            } else if(di[i].type_ == IDelegationRegistry.DelegationType.TOKEN && di[i].contract_ == MAYC) {
                tmpTokenId = di[i].tokenId;
                if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                    TokenStatus memory ts = getTokenStatus(di[i].vault, MAYC, tmpTokenId);
                    checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                    tmpTokens[statusIndex] = ts;
                    statusIndex++;
                }
            }
        }
        tokens = new TokenStatus[](statusIndex);
        for(uint256 i = 0;i < tokens.length;i++) {
            tokens[i] = tmpTokens[i];
        }
    }

    function bakcTokens(address operator) external view returns(TokenStatus[] memory tokens) {
        TokenStatus[] memory tmpTokens = new TokenStatus[](512);
        uint256 statusIndex = 0;
        uint256 tmpTokenId;
        uint256[] memory checked = new uint256[](80);
        uint256 balance = IERC721(BAKC).balanceOf(operator);
        for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
            TokenStatus memory ts = getTokenStatus(operator, BAKC, IERC721Enumerable(BAKC).tokenOfOwnerByIndex(operator, tokenIndex));
            checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
            tmpTokens[statusIndex] = ts;
            statusIndex++;
        }
        IDelegationRegistry.DelegationInfo[] memory di = delegateCash.getDelegationsByDelegate(operator);
        for(uint256 i = 0;i < di.length;i++) {
            if(di[i].type_ == IDelegationRegistry.DelegationType.ALL || (di[i].type_ == IDelegationRegistry.DelegationType.CONTRACT && di[i].contract_ == BAKC)) {
                balance = IERC721(BAKC).balanceOf(di[i].vault);
                for(uint256 tokenIndex = 0;tokenIndex < balance;tokenIndex++) {
                    tmpTokenId = IERC721Enumerable(BAKC).tokenOfOwnerByIndex(di[i].vault, tokenIndex);
                    if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                        TokenStatus memory ts = getTokenStatus(di[i].vault, BAKC, tmpTokenId);
                        checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                        tmpTokens[statusIndex] = ts;
                        statusIndex++;
                    }
                }
            } else if(di[i].type_ == IDelegationRegistry.DelegationType.TOKEN && di[i].contract_ == BAKC) {
                tmpTokenId = di[i].tokenId;
                if((checked[(tmpTokenId>>8)] & (1 << (tmpTokenId & 0xff))) == 0) {
                    TokenStatus memory ts = getTokenStatus(di[i].vault, BAKC, tmpTokenId);
                    checked[(ts.tokenId>>8)] |= (1 << (ts.tokenId & 0xff));
                    tmpTokens[statusIndex] = ts;
                    statusIndex++;
                }
            }
        }
        tokens = new TokenStatus[](statusIndex);
        for(uint256 i = 0;i < tokens.length;i++) {
            tokens[i] = tmpTokens[i];
        }
    }

    function getTokenStatus(address vault, address contract_, uint256 tokenId) internal view returns(TokenStatus memory ts) {
        ts.tokenId = uint16(tokenId);
        ts.delegated = delegateCash.checkDelegateForToken(BORRO_MY_DOGGO, vault, contract_, ts.tokenId);
        ts.claimed = IBAYCSewerPassClaim(SEWER_PASS_CLAIM).checkClaimed((contract_ == BAYC ? 0 : contract_ == MAYC ? 1 : 2), ts.tokenId);
    }
}
