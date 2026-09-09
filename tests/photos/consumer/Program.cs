using System;
using System.Runtime.InteropServices;

string version = Marshal.PtrToStringAnsi(Native.RawVersion());
if (version != "0.22.2-Release" || Native.CmsVersion() != 2190)
    throw new InvalidOperationException("Unexpected native library versions.");

const uint jpegAndZlib = (1u << 7) | (1u << 6);
if ((Native.RawCapabilities() & jpegAndZlib) != jpegAndZlib)
    throw new InvalidOperationException("LibRaw JPEG/zlib support is missing.");

IntPtr raw = Native.RawInit(0);
if (raw == IntPtr.Zero)
    throw new InvalidOperationException("LibRaw initialization failed.");
Native.RawClose(raw);

IntPtr profile = Native.CreateSrgbProfile();
if (profile == IntPtr.Zero || Native.CloseProfile(profile) == 0)
    throw new InvalidOperationException("LCMS profile creation/cleanup failed.");

Console.WriteLine($"NuGet P/Invoke smoke test passed: LibRaw {version}, Little CMS {Native.CmsVersion()}.");

internal static class Native
{
    [DllImport("libraw", EntryPoint = "libraw_version", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr RawVersion();

    [DllImport("libraw", EntryPoint = "libraw_capabilities", CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint RawCapabilities();

    [DllImport("libraw", EntryPoint = "libraw_init", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr RawInit(uint flags);

    [DllImport("libraw", EntryPoint = "libraw_close", CallingConvention = CallingConvention.Cdecl)]
    internal static extern void RawClose(IntPtr raw);

    [DllImport("liblcms2", EntryPoint = "cmsGetEncodedCMMversion", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int CmsVersion();

    [DllImport("liblcms2", EntryPoint = "cmsCreate_sRGBProfile", CallingConvention = CallingConvention.Cdecl)]
    internal static extern IntPtr CreateSrgbProfile();

    [DllImport("liblcms2", EntryPoint = "cmsCloseProfile", CallingConvention = CallingConvention.Cdecl)]
    internal static extern int CloseProfile(IntPtr profile);
}