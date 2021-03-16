// SPDX-License-Identifier: MIT

pragma solidity >0.5.17;
pragma experimental ABIEncoderV2;

interface GemLike {
    function approve(address, uint256) external;

    function transfer(address, uint256) external;

    function transferFrom(
        address,
        address,
        uint256
    ) external;

    function deposit() external payable;

    function withdraw(uint256) external;
}

interface ManagerLike {
    function cdpCan(
        address,
        uint256,
        address
    ) external view returns (uint256);

    function ilks(uint256) external view returns (bytes32);

    function owns(uint256) external view returns (address);

    function urns(uint256) external view returns (address);

    function vat() external view returns (address);

    function open(bytes32, address) external returns (uint256);

    function give(uint256, address) external;

    function cdpAllow(
        uint256,
        address,
        uint256
    ) external;

    function urnAllow(address, uint256) external;

    function frob(
        uint256,
        int256,
        int256
    ) external;

    function flux(
        uint256,
        address,
        uint256
    ) external;

    function move(
        uint256,
        address,
        uint256
    ) external;

    function exit(
        address,
        uint256,
        address,
        uint256
    ) external;

    function quit(uint256, address) external;

    function enter(address, uint256) external;

    function shift(uint256, uint256) external;
}

interface VatLike {

    struct Ilk {
        uint256 Art;   // Total Normalised Debt     [wad]
        uint256 rate;  // Accumulated Rates         [ray]
        uint256 spot;  // Price with Safety Margin  [ray]
        uint256 line;  // Debt Ceiling              [rad]
        uint256 dust;  // Urn Debt Floor            [rad]
    }

    struct Urn {
        uint256 ink;   // Locked Collateral  [wad]
        uint256 art;   // Normalised Debt    [wad]
    }

    function can(address, address) external view returns (uint256);

    function ilks(bytes32)
        external
        view
        returns (Ilk memory);

    function dai(address) external view returns (uint256);

    function urns(bytes32, address) external view returns (Urn memory);

    function frob(
        bytes32,
        address,
        address,
        address,
        int256,
        int256
    ) external;

    function hope(address) external;

    function move(
        address,
        address,
        uint256
    ) external;
}

interface GemJoinLike {
    function dec() external returns (uint256);

    function gem() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}

interface GNTJoinLike {
    function bags(address) external view returns (address);

    function make(address) external returns (address);
}

interface DaiJoinLike {
    function vat() external returns (VatLike);

    function dai() external returns (GemLike);

    function join(address, uint256) external payable;

    function exit(address, uint256) external;
}

interface HopeLike {
    function hope(address) external;

    function nope(address) external;
}

interface EndLike {
    function fix(bytes32) external view returns (uint256);

    function cash(bytes32, uint256) external;

    function free(bytes32) external;

    function pack(uint256) external;

    function skim(bytes32, address) external;
}

interface JugLike {
    function drip(bytes32) external returns (uint256);
}

interface PotLike {
    function pie(address) external view returns (uint256);

    function drip() external returns (uint256);

    function join(uint256) external;

    function exit(uint256) external;
}

interface SpotLike {
    struct Ilk {
        address pip;
        uint256 mat;
    }

    function ilks(bytes32) external view returns (Ilk memory);
}

interface OSMedianizer {
    function read() external view returns (uint256, bool);

    function foresight() external view returns (uint256, bool);
}

interface OracleSecurityModule {
    function peek() external view returns (uint256, bool);

    function peep() external view returns (uint256, bool);

    function users(address) external view returns (bool);

    function bud(address) external view returns (bool);

    function oracle() external view returns (address);
}

interface DssAutoLine {
    function exec(bytes32 _ilk) external returns (uint256);
}
