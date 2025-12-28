import { TerminalLine } from "@/types/game";

export interface CommandDefinition {
  syntax: string;
  description: string;
}

export const commandRegistry: Record<string, CommandDefinition> = {
  help: { syntax: "help", description: "Show the available commands" },
  clear: { syntax: "clear", description: "Clear the terminal buffer" },
  status: { syntax: "status", description: "Show core stats" },
  inbox: { syntax: "inbox", description: "List open missions" },
  read: { syntax: "read <id>", description: "Show mission detail" },
  accept: { syntax: "accept <id>", description: "Accept a mission" },
  missions: { syntax: "missions", description: "List active missions" },
  submit: { syntax: "submit <id>", description: "Submit mission results" },
  "proxy list": { syntax: "proxy list", description: "Show available proxies" },
  "proxy info": { syntax: "proxy info <id>", description: "Show proxy details" },
  "route show": { syntax: "route show", description: "Show current route" },
  "route add": { syntax: "route add <proxy>", description: "Append proxy to route" },
  "route rm": { syntax: "route rm <proxy>", description: "Remove proxy" },
  "route clear": { syntax: "route clear", description: "Clear the current route" },
  scan: { syntax: "scan <host> [--stealth|--aggr]", description: "Run a simulated scan" },
  probe: { syntax: "probe <host> <port>", description: "Probe a single port" },
  fingerprint: { syntax: "fingerprint <host>", description: "Guess the OS" },
  connect: { syntax: "connect <host>", description: "Establish a session" },
  disconnect: { syntax: "disconnect", description: "Drop the connection" },
  exit: { syntax: "exit", description: "Drop a connection or exit" },
  pwd: { syntax: "pwd", description: "Show working directory" },
  ls: { syntax: "ls [path]", description: "List files" },
  cat: { syntax: "cat <file>", description: "Read a remote file" },
  cp: { syntax: "cp <src> <dst>", description: "Copy files" },
  rm: { syntax: "rm <path>", description: "Remove a file" },
  edit: { syntax: "edit <file> key=value", description: "Edit simple metadata" },
  "wipe logs": { syntax: "wipe logs", description: "Clear the log trail" },
  market: { syntax: "market", description: "Inspect the market" },
  buy: { syntax: "buy <item>", description: "Buy a tool" },
};

export function helpOutput(): TerminalLine[] {
  return [
    {
      id: "help-header",
      text: "Available commands:",
      type: "info" as const,
    },
    ...Object.entries(commandRegistry).map(([command, config], index) => ({
      id: `help-${command}-${index}`,
      text: `${config.syntax.padEnd(24)} ${config.description}`,
      type: "info" as const,
    })),
  ];
}
