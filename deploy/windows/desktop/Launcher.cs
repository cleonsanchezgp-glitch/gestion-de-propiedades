using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Windows.Forms;

internal static class Launcher
{
    [STAThread]
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length != 0) throw new InvalidOperationException("Este actualizador se abre sin argumentos.");
            string parent = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "PromalzaUpdate");
            // Never trust a pre-existing staging directory or follow a reparse point.
            if (Directory.Exists(parent) && (File.GetAttributes(parent) & FileAttributes.ReparsePoint) != 0)
                throw new InvalidOperationException("Directorio de mantenimiento no válido.");
            Directory.CreateDirectory(parent);
            var acl = new DirectorySecurity();
            acl.SetOwner(new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null));
            acl.SetAccessRuleProtection(true, false);
            foreach (var sid in new[] { WellKnownSidType.BuiltinAdministratorsSid, WellKnownSidType.LocalSystemSid })
                acl.AddAccessRule(new FileSystemAccessRule(new SecurityIdentifier(sid, null), FileSystemRights.FullControl,
                    InheritanceFlags.ContainerInherit | InheritanceFlags.ObjectInherit, PropagationFlags.None, AccessControlType.Allow));
            Directory.SetAccessControl(parent, acl);
            string stage = Path.Combine(parent, Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(stage, acl);
            var assembly = Assembly.GetExecutingAssembly();
            byte[] bytes;
            using (var stream = assembly.GetManifestResourceStream("payload.zip"))
            using (var memory = new MemoryStream()) { stream.CopyTo(memory); bytes = memory.ToArray(); }
            string expected;
            using (var reader = new StreamReader(assembly.GetManifestResourceStream("payload.sha256"))) expected = reader.ReadToEnd().Trim();
            using (var sha = SHA256.Create())
                if (!String.Equals(BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", ""), expected, StringComparison.OrdinalIgnoreCase))
                    throw new InvalidOperationException("El paquete no supera la comprobación de integridad.");
            using (var memory = new MemoryStream(bytes))
            using (var zip = new ZipArchive(memory, ZipArchiveMode.Read))
            {
                long total = 0;
                foreach (var entry in zip.Entries)
                {
                    string name = entry.FullName;
                    if (name.Contains("\\") || name.Contains(":") || name.StartsWith("/") || name.Contains("..") || name.EndsWith("/"))
                        throw new InvalidOperationException("Ruta de paquete no válida.");
                    string destination = Path.GetFullPath(Path.Combine(stage, name));
                    if (!destination.StartsWith(stage + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || entry.Length > 536870912L)
                        throw new InvalidOperationException("Contenido de paquete no válido.");
                    total += entry.Length;
                    if (total > 1073741824L) throw new InvalidOperationException("Paquete demasiado grande.");
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    using (var input = entry.Open())
                    using (var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                    {
                        var buffer = new byte[65536]; long copied = 0; int count;
                        while ((count = input.Read(buffer, 0, buffer.Length)) != 0)
                        { copied += count; if (copied > entry.Length) throw new InvalidOperationException("Tamaño no válido."); output.Write(buffer, 0, count); }
                        if (copied != entry.Length) throw new InvalidOperationException("Paquete incompleto.");
                    }
                }
            }
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
            var start = new ProcessStartInfo(powershell, "-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File \"" + Path.Combine(stage, "Desktop.ps1") + "\"");
            start.UseShellExecute = false; start.CreateNoWindow = true; start.WorkingDirectory = stage;
            using (var process = Process.Start(start))
            {
                process.WaitForExit();
                if (process.ExitCode != 0) throw new InvalidOperationException("La ventana de actualización no pudo iniciarse.");
                return 0;
            }
            // Keep this private directory for recovery/support; never delete a running operation.
        }
        catch
        {
            MessageBox.Show("No se ha podido abrir el actualizador. No se declara ninguna actualización completada. Contacte con el responsable.",
                "PROMALZA", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 4;
        }
    }
}
