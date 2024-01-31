// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";

contract ShipAssetsUpgradeable is Initializable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    struct Battleship {
        uint seed;
        string classType;
        string color;
        string thrusterColor;
        Part[7] outerParts;
        Part[7] innerParts;
        Part[7] middleParts;
    }

    struct Part {
        string name;
        string value;
        string rarity;
    }

    mapping(string => mapping(uint => Part[])) public partsRarity;

    function initialize() public initializer {
        uint commonPartsIdx = 0;
        uint uncommonPartsIdx = 1;
        uint rarePartsIdx = 2;
        uint epicPartsIdx = 3;
        uint legendaryPartsIdx = 4;

        partsRarity["Thruster"][commonPartsIdx].push(
            Part({name: "Thruster", value: "~~]", rarity: "Common"})
        );

        partsRarity["Thruster"][commonPartsIdx].push(
            Part({name: "Thruster", value: "--]", rarity: "Common"})
        );

        partsRarity["Thruster"][uncommonPartsIdx].push(
            Part({name: "Thruster", value: "-=]", rarity: "Uncommon"})
        );

        partsRarity["Thruster"][uncommonPartsIdx].push(
            Part({name: "Thruster", value: "~=]", rarity: "Uncommon"})
        );

        partsRarity["Thruster"][rarePartsIdx].push(
            Part({name: "Thruster", value: "==)", rarity: "Rare"})
        );

        partsRarity["Thruster"][rarePartsIdx].push(
            Part({name: "Thruster", value: "=:)", rarity: "Rare"})
        );

        partsRarity["Thruster"][epicPartsIdx].push(
            Part({name: "Thruster", value: "==}", rarity: "Epic"})
        );

        partsRarity["Thruster"][epicPartsIdx].push(
            Part({name: "Thruster", value: "=:}", rarity: "Epic"})
        );

        partsRarity["Thruster"][legendaryPartsIdx].push(
            Part({name: "Thruster", value: "==]", rarity: "Legendary"})
        );

        partsRarity["Thruster"][legendaryPartsIdx].push(
            Part({name: "Thruster", value: "=:]", rarity: "Legendary"})
        );

        partsRarity["Shield"][commonPartsIdx].push(
            Part({name: "Shield", value: ")*)", rarity: "Common"})
        );

        partsRarity["Shield"][commonPartsIdx].push(
            Part({name: "Shield", value: ")))", rarity: "Common"})
        );

        partsRarity["Shield"][uncommonPartsIdx].push(
            Part({name: "Shield", value: ")*]", rarity: "Uncommon"})
        );

        partsRarity["Shield"][uncommonPartsIdx].push(
            Part({name: "Shield", value: "))]", rarity: "Uncommon"})
        );

        partsRarity["Shield"][rarePartsIdx].push(
            Part({name: "Shield", value: ")/]", rarity: "Rare"})
        );

        partsRarity["Shield"][rarePartsIdx].push(
            Part({name: "Shield", value: ")]]", rarity: "Rare"})
        );

        partsRarity["Shield"][epicPartsIdx].push(
            Part({name: "Shield", value: "]|]", rarity: "Epic"})
        );

        partsRarity["Shield"][epicPartsIdx].push(
            Part({name: "Shield", value: "]]]", rarity: "Epic"})
        );

        partsRarity["Shield"][legendaryPartsIdx].push(
            Part({name: "Shield", value: "&gt;^&gt;", rarity: "Legendary"})
        );

        partsRarity["Shield"][legendaryPartsIdx].push(
            Part({name: "Shield", value: "&gt;&gt;&gt;", rarity: "Legendary"})
        );

        partsRarity["Cargo"][commonPartsIdx].push(
            Part({name: "Cargo", value: "(%)", rarity: "Common"})
        );

        partsRarity["Cargo"][commonPartsIdx].push(
            Part({name: "Cargo", value: "( )", rarity: "Common"})
        );

        partsRarity["Cargo"][uncommonPartsIdx].push(
            Part({name: "Cargo", value: "{%}", rarity: "Uncommon"})
        );

        partsRarity["Cargo"][uncommonPartsIdx].push(
            Part({name: "Cargo", value: "{ }", rarity: "Uncommon"})
        );

        partsRarity["Cargo"][rarePartsIdx].push(
            Part({name: "Cargo", value: "[%]", rarity: "Rare"})
        );

        partsRarity["Cargo"][rarePartsIdx].push(
            Part({name: "Cargo", value: "[ ]", rarity: "Rare"})
        );

        partsRarity["Cargo"][epicPartsIdx].push(
            Part({name: "Cargo", value: "[^]", rarity: "Epic"})
        );

        partsRarity["Cargo"][legendaryPartsIdx].push(
            Part({name: "Cargo", value: "[-]", rarity: "Legendary"})
        );

        partsRarity["Blaster"][commonPartsIdx].push(
            Part({name: "Blaster", value: ")~~", rarity: "Common"})
        );

        partsRarity["Blaster"][commonPartsIdx].push(
            Part({name: "Blaster", value: ")--", rarity: "Common"})
        );

        partsRarity["Blaster"][uncommonPartsIdx].push(
            Part({name: "Blaster", value: ")=-", rarity: "Uncommon"})
        );

        partsRarity["Blaster"][uncommonPartsIdx].push(
            Part({name: "Blaster", value: ")=~", rarity: "Uncommon"})
        );

        partsRarity["Blaster"][rarePartsIdx].push(
            Part({name: "Blaster", value: "}=+", rarity: "Rare"})
        );

        partsRarity["Blaster"][rarePartsIdx].push(
            Part({name: "Blaster", value: "}==", rarity: "Rare"})
        );

        partsRarity["Blaster"][epicPartsIdx].push(
            Part({name: "Blaster", value: ")&gt;&gt;", rarity: "Epic"})
        );

        partsRarity["Blaster"][epicPartsIdx].push(
            Part({name: "Blaster", value: ")=&gt;", rarity: "Epic"})
        );

        partsRarity["Blaster"][legendaryPartsIdx].push(
            Part({name: "Blaster", value: "]&gt;&gt;", rarity: "Legendary"})
        );

        partsRarity["Blaster"][legendaryPartsIdx].push(
            Part({name: "Blaster", value: "]=&gt;", rarity: "Legendary"})
        );

        partsRarity["Nosecone"][commonPartsIdx].push(
            Part({name: "Nosecone", value: "::&gt;", rarity: "Common"})
        );

        partsRarity["Nosecone"][commonPartsIdx].push(
            Part({name: "Nosecone", value: "**&gt;", rarity: "Common"})
        );

        partsRarity["Nosecone"][uncommonPartsIdx].push(
            Part({name: "Nosecone", value: "}}&gt;", rarity: "Uncommon"})
        );

        partsRarity["Nosecone"][uncommonPartsIdx].push(
            Part({name: "Nosecone", value: ") &gt;", rarity: "Uncommon"})
        );

        partsRarity["Nosecone"][rarePartsIdx].push(
            Part({name: "Nosecone", value: "::}", rarity: "Rare"})
        );

        partsRarity["Nosecone"][epicPartsIdx].push(
            Part({name: "Nosecone", value: "}:}", rarity: "Epic"})
        );

        partsRarity["Nosecone"][epicPartsIdx].push(
            Part({name: "Nosecone", value: "} }", rarity: "Epic"})
        );

        partsRarity["Nosecone"][legendaryPartsIdx].push(
            Part({name: "Nosecone", value: "&gt;*&gt;", rarity: "Legendary"})
        );

        partsRarity["Nosecone"][legendaryPartsIdx].push(
            Part({name: "Nosecone", value: "&gt; &gt;", rarity: "Legendary"})
        );

        partsRarity["Cockpit"][commonPartsIdx].push(
            Part({name: "Cockpit", value: ":o ", rarity: "Common"})
        );

        partsRarity["Cockpit"][commonPartsIdx].push(
            Part({name: "Cockpit", value: " o ", rarity: "Common"})
        );

        partsRarity["Cockpit"][uncommonPartsIdx].push(
            Part({name: "Cockpit", value: ":O ", rarity: "Uncommon"})
        );

        partsRarity["Cockpit"][uncommonPartsIdx].push(
            Part({name: "Cockpit", value: " O ", rarity: "Uncommon"})
        );

        partsRarity["Cockpit"][rarePartsIdx].push(
            Part({name: "Cockpit", value: " 0 ", rarity: "Rare"})
        );

        partsRarity["Cockpit"][epicPartsIdx].push(
            Part({name: "Cockpit", value: "OoO", rarity: "Epic"})
        );

        partsRarity["Cockpit"][epicPartsIdx].push(
            Part({name: "Cockpit", value: "o0o", rarity: "Epic"})
        );

        partsRarity["Cockpit"][legendaryPartsIdx].push(
            Part({name: "Cockpit", value: "000", rarity: "Legendary"})
        );

        partsRarity["Cockpit"][legendaryPartsIdx].push(
            Part({name: "Cockpit", value: "0O0", rarity: "Legendary"})
        );

        partsRarity["Aero"][commonPartsIdx].push(
            Part({name: "Aero", value: "__)", rarity: "Common"})
        );

        partsRarity["Aero"][uncommonPartsIdx].push(
            Part({name: "Aero", value: "_))", rarity: "Uncommon"})
        );

        partsRarity["Aero"][rarePartsIdx].push(
            Part({name: "Aero", value: "__}", rarity: "Rare"})
        );
        partsRarity["Aero"][epicPartsIdx].push(
            Part({name: "Aero", value: "_//", rarity: "Epic"})
        );

        partsRarity["Aero"][epicPartsIdx].push(
            Part({name: "Aero", value: "__/", rarity: "Epic"})
        );

        partsRarity["Aero"][legendaryPartsIdx].push(
            Part({name: "Aero", value: "/_/", rarity: "Legendary"})
        );

        partsRarity["Aero"][legendaryPartsIdx].push(
            Part({name: "Aero", value: "__&gt;", rarity: "Legendary"})
        );
    }

    function getRandomIndexBasedOnRarity(
        uint256 seed
    ) public pure returns (uint256) {
        uint randomNumber = seed % 100;

        uint[5] memory rarityIndices = [
            uint(0),
            uint(1),
            uint(2),
            uint(3),
            uint(4)
        ];

        uint[5] memory weights = [
            uint(35),
            uint(30),
            uint(20),
            uint(10),
            uint(5)
        ];

        for (uint i = 0; i < weights.length; i++) {
            if (randomNumber < weights[i]) {
                return rarityIndices[i];
            }

            randomNumber -= weights[i];
        }

        return 0;
    }

    function generateRandomNeonColor(
        uint seed
    ) public pure returns (string memory) {
        uint[3] memory colors = [
            uint(seed % 255),
            uint(seed % 255),
            uint(seed % 255)
        ];

        uint randIdx = seed % colors.length;

        colors[randIdx] = 255;

        uint randIdx2 = seed % colors.length;
        while (randIdx2 == randIdx) {
            randIdx2 = ++seed % colors.length;
        }

        colors[randIdx2] = 0;

        return
            string.concat(
                "rgb(",
                StringsUpgradeable.toString(colors[0]),
                ",",
                StringsUpgradeable.toString(colors[1]),
                ",",
                StringsUpgradeable.toString(colors[2]),
                ")"
            );
    }

    function getRandomClass(uint256 seed) public pure returns (string memory) {
        string[5] memory classes = [
            "Fighter",
            "Cruiser",
            "Gunship",
            "Voyager",
            "Alien"
        ];

        return classes[seed % classes.length];
    }

    function getRandomPart(
        uint256 seed,
        string memory partType,
        uint partVariance
    ) public view returns (Part memory) {
        string memory emptyPartType = "Empty";
        if (equal(partType, emptyPartType)) {
            return Part({name: "Empty", value: "   ", rarity: "Common"});
        }

        uint idx = getRandomIndexBasedOnRarity(seed + partVariance);

        return
            partsRarity[partType][idx][
                seed % partsRarity[partType][idx].length
            ];
    }

    function getRandomParts(
        uint seed,
        string[7] memory partTypes,
        uint[7] memory partVariance
    ) public view returns (Part[7] memory) {
        Part[7] memory parts;

        for (uint i = 0; i < partTypes.length; i++) {
            parts[i] = getRandomPart(seed, partTypes[i], partVariance[i]);
        }

        return parts;
    }

    function createBattleship(
        uint seed,
        string memory classType,
        string memory color,
        string memory thrusterColor,
        Part[7] memory outerParts,
        Part[7] memory innerParts,
        Part[7] memory middleParts
    ) public pure returns (Battleship memory) {
        Battleship memory ship = Battleship({
            seed: seed,
            classType: classType,
            color: color,
            thrusterColor: thrusterColor,
            outerParts: outerParts,
            innerParts: innerParts,
            middleParts: middleParts
        });

        return ship;
    }

    function buildBattleship(
        uint256 seed
    ) public view returns (Battleship memory) {
        string memory classType = getRandomClass(seed);
        string memory color = generateRandomNeonColor(seed);

        uint256[7] memory partVariance1 = [
            uint256(1),
            uint256(3),
            uint256(5),
            uint256(8),
            uint256(13),
            uint256(21),
            uint256(34)
        ];

        uint256[7] memory partVariance2 = [
            uint256(2),
            uint256(3),
            uint256(5),
            uint256(7),
            uint256(11),
            uint256(13),
            uint256(15)
        ];

        uint256[7] memory partVariance3 = [
            uint256(4),
            uint256(8),
            uint256(16),
            uint256(32),
            uint256(64),
            uint256(128),
            uint256(256)
        ];

        string memory thrusterColor = generateRandomNeonColor(
            seed % partVariance3[seed % partVariance3.length]
        );

        // ship shapes must be shifted to the end of the rows.
        if (equal(classType, "Fighter")) {
            return
                createBattleship(
                    seed,
                    "Fighter",
                    color,
                    thrusterColor,
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Empty",
                            "Aero",
                            "Nosecone",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance1
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Empty",
                            "Aero",
                            "Aero",
                            "Nosecone",
                            "Empty",
                            "Empty"
                        ],
                        partVariance2
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Shield",
                            "Cockpit",
                            "Nosecone",
                            "Blaster",
                            "Empty"
                        ],
                        partVariance3
                    )
                );
        }

        if (equal(classType, "Cruiser")) {
            return
                createBattleship(
                    seed,
                    "Cruiser",
                    color,
                    thrusterColor,
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Blaster",
                            "Empty",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance1
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Cargo",
                            "Blaster",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance2
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Nosecone",
                            "Shield",
                            "Shield",
                            "Cockpit",
                            "Nosecone",
                            "Empty"
                        ],
                        partVariance3
                    )
                );
        }

        if (equal(classType, "Gunship")) {
            return
                createBattleship(
                    seed,
                    "Gunship",
                    color,
                    thrusterColor,
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Empty",
                            "Thruster",
                            "Blaster",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance1
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Aero",
                            "Aero",
                            "Blaster",
                            "Empty",
                            "Empty"
                        ],
                        partVariance2
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Empty",
                            "Shield",
                            "Cargo",
                            "Cockpit",
                            "Blaster",
                            "Empty"
                        ],
                        partVariance3
                    )
                );
        }

        if (equal(classType, "Voyager")) {
            return
                createBattleship(
                    seed,
                    "Voyager",
                    color,
                    thrusterColor,
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Aero",
                            "Aero",
                            "Blaster",
                            "Empty",
                            "Empty"
                        ],
                        partVariance1
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Nosecone",
                            "Empty",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance2
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Shield",
                            "Cargo",
                            "Cockpit",
                            "Nosecone",
                            "Empty"
                        ],
                        partVariance3
                    )
                );
        }

        if (equal(classType, "Alien")) {
            return
                createBattleship(
                    seed,
                    "Alien",
                    color,
                    thrusterColor,
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Aero",
                            "Aero",
                            "Aero",
                            "Blaster",
                            "Empty"
                        ],
                        partVariance1
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Thruster",
                            "Shield",
                            "Shield",
                            "Blaster",
                            "Empty",
                            "Empty"
                        ],
                        partVariance2
                    ),
                    getRandomParts(
                        seed,
                        [
                            "Empty",
                            "Empty",
                            "Cockpit",
                            "Nosecone",
                            "Empty",
                            "Empty",
                            "Empty"
                        ],
                        partVariance3
                    )
                );
        }

        revert("Invalid class type");
    }

    function equal(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

