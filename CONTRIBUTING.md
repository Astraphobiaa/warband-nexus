# Contributing to Warband Nexus

Thank you for your interest in contributing to **Warband Nexus**! We welcome bug reports, feature suggestions, and code contributions from the community.

## How to Contribute

### Reporting Bugs

1. Check existing [Issues](https://github.com/Astraphobiaa/warband-nexus/issues) to avoid duplicates.
2. Open a new issue with a clear title and detailed description.
3. Include steps to reproduce, expected behavior, and actual behavior.
4. If possible, include screenshots or error logs (from `/wn debug`).

### Suggesting Features

1. Open an issue with the **Feature Request** label.
2. Describe the feature, why it would be useful, and any implementation ideas.

### Submitting Code (Pull Requests)

1. **Fork** the repository and create a new branch from `main`.
2. Make your changes in your branch.
3. Test your changes in-game to ensure they work correctly.
4. Submit a **Pull Request** (PR) with a clear description of the changes.

### Code Guidelines

- Follow the existing code style and patterns in the project.
- Use the established factory patterns (`ns.UI.Factory`) for UI components.
- All user-facing strings must use the localization system (`ns.L`).
- Keep performance in mind — avoid unnecessary frame updates and iterations.
- Use the existing event-driven architecture (`WarbandNexus:RegisterMessage` / `SendMessage`).

### Localization

- Locale files are in the `Locales/` directory.
- If you add new user-facing strings, add them to **all** locale files.
- `enUS.lua` is the base — other locales can fall back to English.

## License & Contribution Agreement

This project is licensed under **All Rights Reserved** (see [LICENSE](LICENSE)).

By submitting a Pull Request, you agree that:

- Your contribution will be licensed under the same terms as the project.
- You grant the project maintainer (Mert Gedikli) full rights to use, modify, and distribute your contribution as part of this project.
- You confirm that your contribution is your own original work, or you have the right to submit it.

## Code of Conduct

- Be respectful and constructive in all interactions.
- Focus on the project and its improvement.
- No harassment, discrimination, or toxic behavior.

## Questions?

If you have any questions about contributing, feel free to open an issue or reach out to the maintainer.

---

Thank you for helping make Warband Nexus better!
