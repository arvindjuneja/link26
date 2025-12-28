import { SaveProvider } from "./saveProvider";

export const cloudSaveProvider: SaveProvider = {
  async load() {
    console.info("Cloud save is coming soon.");
    return null;
  },
  async save() {
    console.info("Cloud save is coming soon.");
  },
  async clear() {
    console.info("Cloud save is coming soon.");
  },
};
