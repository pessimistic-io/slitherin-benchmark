//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;

interface IBattleflyComic {
    struct Comic {
        uint256 id;
        bool active;
        // 1 = V1/V2 staked + buyable, 2 = battlefly staked + buyable, 3 = burn result, 4 only mintable by treasury
        uint256 mintType;
        uint256 priceInWei;
        uint256 burnableIn;
        uint256 burnAmount;
        uint256 maxPaidMintsPerWallet;
        uint256 maxMints;
        string name;
        string uri;
    }

    function uri(uint256 _comicId) external view returns (string memory);

    function updateURI(uint256 _comicId, string memory _newUri) external;

    function mintFounders(uint256[] memory tokenIds, uint256 id) external;

    function mintBattlefly(uint256[] memory tokenIds, uint256 id) external;

    function mintPaid(uint256 amount, uint256 id) external;

    function burn(
        uint256 burnId,
        uint256 amount,
        uint256 mintId
    ) external;

    event MintComicWithFounder(address indexed sender, uint256 indexed comicId, uint256[] usedFounderIds);
    event MintComicWithBattlefly(address indexed sender, uint256 indexed comicId, uint256[] usedBattleflyIds);
    event MintComicWithPayment(address indexed sender, uint256 indexed comicId, uint256 amount);
    event MintComicByBurning(
        address indexed sender,
        uint256 indexed comicToBeBurnt,
        uint256 amount,
        uint256 indexed comicId
    );
    event MintComicWithTreasury(address indexed treasury, uint256 indexed comicId, uint256 amount);
    event NewComicAdded(
        uint256 indexed comicId,
        bool active,
        uint256 mintType,
        uint256 priceInWei,
        uint256 burnableIn,
        uint256 burnAmount,
        uint256 maxPaidMintsPerWallet,
        uint256 maxMints,
        string name,
        string uri
    );
    event UpdateComicURI(uint256 indexed comicId, string newUri);
    event ComicActivated(uint256 indexed comicId, bool activated);
    event ComicUpdated(
        uint256 comicId,
        bool active,
        uint256 mintType,
        uint256 priceInWei,
        uint256 burnableIn,
        uint256 burnAmount,
        uint256 maxPaidMintsPerWallet,
        uint256 maxMints,
        string name,
        string uri
    );
}

