// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import "./Math.sol";
import "./Address.sol";
import "./ERC165Checker.sol";
import "./IERC20Metadata.sol";
import "./IERC721Metadata.sol";

contract Loader {
    struct Request {
        address addr;
        uint256[] tokenIds;
    }

    struct Response {
        bool isContract;
        bool supportsERC20;
        bool supportsERC721;
        uint256 balance;
        string name;
        string symbol;
        uint8 decimals;
        string[] tokenURIs;
    }

    function load(
        address owner,
        Request[] calldata requests
    ) external view returns (Response[] memory responses) {
        responses = new Response[](requests.length);

        for (uint256 i; i < requests.length; i++) {
            Request calldata request = requests[i];
            Response memory response = responses[i];

            response.isContract = Address.isContract(request.addr);
            if (!response.isContract) {
                continue;
            }

            response.supportsERC20 = ERC165Checker.supportsInterface(
                request.addr,
                type(IERC20).interfaceId
            );

            response.supportsERC721 = ERC165Checker.supportsInterface(
                request.addr,
                type(IERC721).interfaceId
            );

            // prettier-ignore
            try IERC20(request.addr).balanceOf{gas: 50_000}(owner) returns (uint256 balance) {
                response.balance = balance;
            } catch {
            }

            // prettier-ignore
            try IERC20Metadata(request.addr).name{gas: 100_000}() returns (string memory name) {
                response.name = name;
            } catch {
            }
            // prettier-ignore
            try IERC20Metadata(request.addr).symbol{gas: 100_000}() returns (string memory symbol) {
                response.symbol = symbol;
            } catch {
            }
            // prettier-ignore
            try IERC20Metadata(request.addr).decimals{gas: 30_000}() returns (uint8 decimals) {
                response.decimals = decimals;
            } catch {
            }

            response.tokenURIs = new string[](request.tokenIds.length);

            for (uint j; j < request.tokenIds.length; j++) {
                uint256 tokenId = request.tokenIds[i];
                // prettier-ignore
                try IERC721Metadata(request.addr)
                        .tokenURI{gas: 100_000}(tokenId) returns (string memory uri) {
                    response.tokenURIs[j] = uri;
                } catch {
                }
            }
        }
    }
}

